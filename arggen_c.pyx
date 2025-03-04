import datetime
import json
import jsonschema
import sys
import re

schemaFile:str = '../argspec/coder-arguments-schema.json'

arggenVersion:str = 'v1.0.0'

argHeader:str = 'Argument parser generated by arggen %s at %s' % (arggenVersion, datetime.datetime.now())

def printe(arg:object) -> None:
    print(str(arg), file=sys.stderr)

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

def toC(spec:dict, headerFile:str) -> int:
    args:list = spec['args']
    program = spec['program'] if 'program' in spec else 'asdf'
    argTypeMap:dict = {
        'flag' : 'bool',
        'string' : 'char*',
        'int' : 'int',
        'char' : 'char',
        'help' : 'bool'
    }

    helpOpt:str = ''

    argSpecSetup:str = (
        f'#include "{headerFile}"'
    )

    # TODO: Add in help lines
    helpParts:list = []
    usage:list = []
    parserParts:list = []
    argsStructParts:list = []
    headerLines:list = []
    initialiserLines:list = []

    for arg in args:
        parserActions:list = []
        argType = argTypeMap[arg['type']]
        argsStructParts.append('\t%s %s;' % (argType, arg['dest']))
        shortAndLongArePresent:bool = 'short' in arg and 'long' in arg
        helpParts.append(((arg['short'] if 'short' in arg else '') + (', ' if shortAndLongArePresent else '') + (arg['long'] if 'long' in arg else ''), arg['help']))
        argDest:str = arg['dest']
        defaultValue:str = wrapDefaultValue(arg['default'], arg['type'])
        initialiserLines.append(f'\targs->{argDest} = {defaultValue};')
        if arg['type'] == 'flag':
            parserActions = [f"\t\t\targs->{arg['dest']} = true;"]
            usage.append(arg['short'] if 'short' in arg else arg['long'])
        elif arg['type'] == 'help':
            parserActions = ['\t\t\tshowHelp = true;']
            usage.append(arg['short'] if 'short' in arg else arg['long'])
            if helpOpt == '':
                helpOpt = arg['short'] if 'short' in arg else arg['long']
        else:
            # TODO: Check that charactar input is unit length
            argGrabber:str = ''
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
                    '\t\t\t\tfailed = true;',
                    '\t\t\t\tbreak;',
                    '\t\t\t}'
                ]
            usage.append((arg['short'] if 'short' in arg else arg['long']) + ' ' + arg['dest'].upper())
        shortHandler = ('strcmp("%s", argv[i]) == 0' % arg['short']) if 'short' in arg else ''
        longHandler = ('strcmp("%s", argv[i]) == 0' % arg['long']) if 'long' in arg else ''
        shortLongConnective = ' || ' if 'short' in arg and 'long' in arg else ''
        parserParts += [
            # TODO: Allow a missing short or long option
            '\t\t%sif (%s%s%s)' %('' if parserParts == [] else 'else ', shortHandler, shortLongConnective, longHandler), 
            '\t\t{'
        ] + parserActions + [
            '\t\t}'
        ]

    usage.sort()
    usageString:str = '[' + ' | '.join(usage) + ']'

    helpLines:list = []
    maxLen:int = len(max(list(map(lambda part: part[0], helpParts)), key=len))
    helpParts.sort(key=lambda part:re.sub(r'^--', r'-', part[0]))
    for (opt, hlp) in helpParts:
        helpLines.append((' ' * 8 if not opt.startswith('--') else ' ' * 7) + opt + (' ' * (maxLen - len(opt) + (8 if not opt.startswith('--') else 9))) + hlp)
    
    for i in range(len(helpLines)):
        helpLines[i] = f'\t\tprintf("%s\\n", "{helpLines[i]}");'

    helpHandler:list = []
    helpGuard:str = '\tif (showHelp || failed)'
    helpHandler = [
        '\tif (failed)',
        '\t{',
        f'\t\tfprintf(stderr, "%s %s %s\\n", "usage:", argv[0], "{usageString}");',
        f'\t\tfprintf(stderr, "%s %s %s %s\\n", "Try `", argv[0], "{helpOpt}\'", "for more information");',
        '\t\texit(-1);',
        '\t}',
        '',
        '\tif (showHelp)',
        '\t{',
        f'\t\tfprintf(stderr, "%s %s %s\\n", "usage:", argv[0], "{usageString}");',
        '\t\tprintf("%s\\n", "Options and arguments");'
    ] + helpLines + [
        '\t\texit(0);',
        '\t}'
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
        '\tbool failed = false;',
        '\tbool showHelp = false;',
        '\tfor (int i = 1; i < argc; i++)', 
        '\t{'
    ] + parserParts  + [
        '\t\telse',
        '\t\t{',
        '\t\t\tfprintf(stderr, "%s %s\\n", "Unknown option:", argv[i]);',
        '\t\t\tfailed = true;',
        '\t\t\tbreak;',
        '\t\t}',
        '\t}',
        '\t'
    ] + helpHandler + [
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
    print('\n'.join(parserLines))

    with open(headerFile, 'w+') as o:
        o.write('\n'.join(headerLines))
    return 0

def standardise(spec:dict, schema:dict) -> dict:
    # Precondition: the spec has been validated against the schema
    if 'program' not in spec:
        spec['program'] = schema['program']['default']
    if 'args' not in spec:
        spec['args'] = []
    else:
        for arg in spec['args']:
            if 'help' not in arg:
                arg['help'] = ''

    return spec

def main(args:[str]) -> int:
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

    spec = standardise(spec, schema)

    cHeader:str = (spec['program'] + '_arg_parser.h')

    return toC(spec, cHeader)

if __name__ == '__main__':
    try:
        sys.exit(main(sys.argv[1:]))
    except KeyboardInterrupt as ke:
        printe(ke)
        sys.exit(1)