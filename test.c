#include "tester_arg_parser.h"

#include <stdio.h>

int main(int argc, char **argv)
{
	printf("%s\n", "Parsing arguments...");
	args_t *args = parseArgs(argc, argv);
	printf("%s\n", "Parsing arguments2...");
	printf("%d\n", args->x);
	return 0;

	// TODO: initialise strings
}