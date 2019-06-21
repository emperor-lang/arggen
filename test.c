#include "tester_arg_parser.h"

#include <stdio.h>

int main(int argc, char **argv)
{
	printf("%s\n", "Parsing arguments...");
	args_t *args = parseArgs(argc, argv);
	printf("%s\n", "Done parsing arguments...");
	printf("%s => '%s'\n", "args->file", args->file);
	printf("%s => '%s'\n", "args->out", args->out);
	printf("%s => '%s'\n", "args->verbose", args->verbose);
	printf("%s => '%d'\n", "args->x", args->x);

	free(args);
	return 0;
}	