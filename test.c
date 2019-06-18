#include "tester_arg_parser.h"

#include <stdio.h>

int main(int argc, char **argv)
{
	args_t args = parseArgs(argc, argv);
	printf("%s\n", args.verbose);
	return 0;
}