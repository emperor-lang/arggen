#include "tester_arg_parser.h"

#include <stdio.h>

int main(int argc, char **argv)
{
	printf("%s\n", "Parsing arguments...");
	args_t *args = parseArgs(argc, argv);
	printf("%s\n", "Done parsing arguments...");
	printf("%d\n", args->x);

	// TODO: initialise strings
	// TODO: add a destructor

	free(args);
	return 0;
}