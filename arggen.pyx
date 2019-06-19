import datetime
import json
import jsonschema
import sys

schemaFile:str = '../argspec/arguments.schema.json'

arggenVersion:str = 'v1.0.0'

argHeader:str = 'Argument parser generated by arggen %s at %s' % (arggenVersion, datetime.datetime.now())

def printe(arg:str) -> None:
    print(arg, file=sys.stderr)

def wrapDefaultValue(value:str, valueType:str) -> str:
    if valueType == 'string':
        return f'"{value}"'
    elif valueType == 'char':
        return f"'{value}'"
    else:
        return value

# # Setup draft 7 validator to replace defaults
# # Helpfully transposed from 
# # https://stackoverflow.com/questions/41290777/trying-to-make-json-schema-validator-in-python-to-set-default-values
# def extendValidatorToAddDefaults(validator:object) -> object:
#     propertyValidator = validator.VALIDATORS["properties"]

#     def setDefaultValues(val, properties, instance:dict, schema:dict):
#         for property_, subschema in properties.items():
#             if "default" in subschema and not isinstance(instance, list):
#                 instance.setdefault(property_, subschema["default"])

#         for error in setDefaultValues(val, properties, instance, schema):
#             yield error

#     return jsonschema.validators.extend(validator, {"properties": setDefaultValues})

# jsonschema.FillDefaultValidatingDraft7Validator = extendValidatorToAddDefaults(jsonschema.Draft7Validator)

def isValidDest(dest:str) -> bool:
    return len(dest) > 0 and 'a' < dest[0] and dest[0] < 'z' and ' ' not in dest

def toHaskell(spec:dict) -> int:
    typeMap:dict = {
        'string' : 'String',
        'char' : 'Char',
        'int' : 'Integer',
        'flag' : 'Bool',
        'help': 'Bool'
    }

    imports:str = 'module Args where\nimport System.Environment\nimport Data.Char\nimport Data.List\n\nnewtype Error = Error String'

    argSpecSetup:str = (
    'parseArgv :: IO Args\n'
    'parseArgv = do \n'
    '    args <- getArgs \n'
    '    return $ parseArgs\' args\n'
    '\n'
    'parseArgs :: [String] -> Args\n'
    'parseArgs args = parseArgs\' args\n'
    '\n'
    'makeChar :: String -> Char\n'
    'makeChar [] = error "Characters should be non-empty"\n'
    'makeChar xs\n'
    '    | length xs == 0 = error "Please give a character"\n'
    '    | length xs >= 2 = error "Too many characters given, expected one here"\n'
    '    | otherwise = xs!!0\n'
    )

    matchLines:[str] = ['parseArgs\' :: [String] -> Args']
    validatorLines:[str] = ['validArg :: (String,String) -> Bool']
    argTypes:str = ''
    defaultArgs:[str] = []

    for arg in spec['args']:
        # if arg['optional']:
        shortName:str = arg['short']
        longName:str = arg['long']
        dest:str = arg['dest']
        argtype:str = typeMap[arg['type']]
        default = arg['default']

        if not isValidDest(dest):
            printe(f'Invalid destination: "{dest}"')
            return 1

        getArgString:str
        argGrabber:str
        if argtype == 'Integer':
            argGrabber = ':x'
            getArgString = f'read x :: Integer'
        elif argtype == 'Char':
            argGrabber = ':c'
            getArgString = f'makeChar c'
        elif argtype == 'Bool':
            argGrabber = ''
            getArgString = 'True'
        else:
            argGrabber = ':u'
            getArgString = 'u'
        # if argtype == 'String':
        # = f'read x :: {argtype} ' 
        #  argtype != 'Char' else 'x'


        matchLines.append(f'parseArgs\' ("{shortName}"{argGrabber}:args) = (parseArgs\' args) {{ {dest} = {getArgString} }}')
        matchLines.append(f'parseArgs\' ("{longName}"{argGrabber}:args) = (parseArgs\' args) {{ {dest} = {getArgString} }}')
        validatorLines.append(f'validArg ("{dest}",s) = isNum s')

        formattedDefault = wrapDefaultValue(default, arg['type'])
        defaultArgs.append(f'{dest} = {formattedDefault}')
        argTypes += (', ' if argTypes != '' else '') + f'{dest} :: {argtype}'
        # else:
        #     matchLines.append(f'parseArgs\' (a:as) = parseArgs\' as ++ [("{dest}",a)]')
        #     validatorLines.append(f'validArg ("{dest}",s) = isFileName s')
            

    matchLines.append('parseArgs\' [] = defaultArgs\n')
    matchLines.append('parseArgs\' args = error $ "Could not parse rest of arguments: " ++ (intercalate " " args)')
    validatorLines.append('validArg _ = True')
    argTypes = f'data Args = Args {{ {argTypes} }}\n    deriving Show'
    defaultArgsString:str = ', '.join(defaultArgs)
    defaultArgsString = f'defaultArgs :: Args\ndefaultArgs = Args {{ {defaultArgsString} }}'

    print('-- %s' % argHeader, end='\n\n')
    print(imports)
    print(argTypes, end='\n\n')
    print(defaultArgsString)
    print(argSpecSetup)
    print('\n'.join(matchLines), end='\n\n')
    # print('\n'.join(validatorLines))

def toC(spec:dict, headerFile:str) -> int:
    args:list = spec['args']
    program = spec['program'] if 'program' in spec else 'asdf'
    argTypeMap:dict = {
        'flag' : 'bool',
        'string' : 'char*',
        'int' : 'int',
        'char' : 'char',
        'help' : 'help'
    }

    argSpecSetup:str = (
        f'#include "{headerFile}"'
    )

    # TODO: Add in help lines
    helpLines:list = []
    parserParts:list = []
    argsStructParts:list = []
    headerLines:list = []
    initialiserLines:list = []

    for arg in args:
        parserActions:list = []
        argType = argTypeMap[arg['type']]
        argsStructParts.append('\t%s %s;' % (argType, arg['dest']))
        if arg['type'] == 'flag':
            parserActions = [f"\t\t\targs->{arg['dest']} = true;"]
        else:
            # TODO: Check that charactar input is unit length
            argGrabber:str = ''
            argDest:str = arg['dest']
            defaultValue:str = wrapDefaultValue(arg['default'], arg['type'])
            initialiserLines.append(f'\targs->{argDest} = {defaultValue};')
            if arg['type'] == 'string':
                argGrabber = 'argv[++i]'
            elif arg['type'] == 'char':
                argGrabber = 'argv[++i][0]'
            elif arg['type'] == 'int':
                argGrabber = 'atoi(argv[++i])'
            parserActions = [
                    '\t\t\tif (i + 1 < argc)',
                    '\t\t\t{',
                    f'\t\t\t\targs->{argDest} = {argGrabber};', #if arg['type'] != 'string' else f'\t\t\t\tstrcpy(args->{argDest}, {argGrabber});',
                    '\t\t\t}',
                    '\t\t\telse',
                    '\t\t\t{',
                    f'\t\t\t\tfprintf(stderr, "%s: %s %s\\n", argv[0], "please add argument for last option specified,", "{argDest.upper()}");',
                    '\t\t\t\texit(-1);',
                    '\t\t\t}'
                ]
        parserParts += [
            '\t\t%sif (strcmp("%s", argv[i]) == 0 || strcmp("%s", argv[i]) == 0)' %('' if parserParts == [] else 'else ', arg['short'], arg['long']), 
            '\t\t{'
        ] + parserActions + [
            '\t\t}'
        ]
        
    argsStructLines:list = [
        'typedef struct args', 
        '{'
    ] + argsStructParts + [
        '} args_t;'
    ]
    parserLines:list = [
        'args_t *parseArgs(int argc, char **argv)', 
        '{', 
        '\targs_t *args = initArgs();', 
        '\tfor (int i = 1; i < argc; i++)', 
        '\t{'
    ] + helpLines + parserParts  + [
        '\t\telse',
        '\t\t{',
        '\t\t\tfprintf(stderr, "%s %s\\n", "Unrecognised argument,", argv[i]);',
        '\t\t\texit(-1);',
        '\t\t}',
        '\t}',
        '\t',
        '\treturn args;',
        '}'
    ]

    initialiserLines = [
        'args_t *initArgs()',
        '{',
        '\targs_t *args = (args_t*)malloc(sizeof(args_t));',
        '\tif (args == NULL)',
        '\t{',
        '\t\tfprintf(stderr, "%s\\n", "Could not allocate space when initialising argument struct");',
        '\t\texit(-1);',
        '\t}'
    ] + initialiserLines + [
        '\treturn args;',
        '}'
    ]

    sanitisedHeaderFile:str = headerFile.replace('.', '_')
    headerLines = [
        f'#ifndef {sanitisedHeaderFile.upper()}_H',
        f'#define {sanitisedHeaderFile.upper()}_H',
        '',
        '#include <stdio.h>',
        '#include <stdlib.h>',
        '#include <stdbool.h>',
        '#include <string.h>',
        '#include <ctype.h>',
        ''
    ] + argsStructLines + [
        '',
        'args_t *parseArgs(int argc, char **argv);',
        'args_t *initArgs();',
        '',
        '#endif'
    ]

    print('// %s' % argHeader, end='\n\n')
    print(argSpecSetup, end='\n\n')
    print('\n'.join(initialiserLines), end='\n\n')
    print('\n'.join(parserLines), end='\n\n')

    with open(headerFile, 'w+') as o:
        o.write('\n'.join(headerLines))
    return 0

def toPython(spec:dict) -> int:
    printe('Python is not yet supported!')
    return -1

def standardise(spec:dict, schema:dict) -> dict:
    return spec

def main(args:[str]) -> int:
    if len(args) < 1:
        printe('More arguments please!')
        return -1

    # inputFileList:list = list(filter(lambda arg: arg[0] != '-', args))
    languageFlagList:list = list(filter(lambda arg: arg[0] == '-', args))

    # if len(inputFileList) == 0:
    #     printe('Please specify an input file')
    #     exit(-1)
    
    if len(languageFlagList) == 0:
        printe('Please specify a langauge flag')
        return -1

    # inputFile:str = inputFileList[0]
    languageFlag:str = languageFlagList[0]

    spec:dict
    try:
        spec = json.load(sys.stdin)
    except json.decoder.JSONDecodeError as jsonde:
        printe(str(jsonde) + f' while handling json from stdin')
        return -1

    schema:dict
    with open(schemaFile, 'r+') as i:
        try:
            schema = json.load(i)
        except json.decoder.JSONDecodeError as jsonde:
            printe(str(jsonde) + f' while handling schema in "{schemaFile}"')
            return -1

    try:
        jsonschema.validate(instance=spec, schema=schema)
    except jsonschema.exceptions.ValidationError as ve:
        printe(f'Input specification did not match the schema (using schema: "{schemaFile}"')
        printe(str(ve))
        return -1

    # TODO: Standardise input here!
    # spec = standardise(spec, jsonschema)
    cHeader:str = (spec['program'] + '_arg_parser.h')

    haskell:bool = False
    C:bool = False
    python:bool = False

    if languageFlag == '-H' or languageFlag == '--haskell':
        haskell = True
    elif languageFlag == '-C' or languageFlag == '--clang':
        C = True
    elif languageFlag == '-P' or languageFlag == '--python':
        python = True

    if haskell:
        return toHaskell(spec)
    elif C:
        return toC(spec, cHeader)
    elif python:
        return toPython(spec)
    else:
        printe('No language specified')
        return -1

if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))