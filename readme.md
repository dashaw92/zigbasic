## Shortcomings (that I know about)

* Extremely fragile interpreter. I didn't even try to make this robust, so malformed BASIC will most likely mimic g++ error messages.
* Order of operations simply does not exist. To get correct math evaluation, use a copious amount of parentheses:
	2 + 3 * 2 incorrectly evaluates to 8, but 2 * (3 + 2) correctly produces 10.
* Very limited feature set. The goal was to produce a minimal functional BASIC interpreter for use on the Pi Pico.
* Unary negation is beyond my comprehension for some reason, so if you want negative literals, do (0 - number): -5 == (0 - 5)

## Keyword reference

| Keyword | Syntax           | Description |
|---------|------------------|-------------|
| PRINT   | PRINT (expr) | Evaluate the expression and print it |
| PRINTNL | PRINTNL (expr) | Same as print but without adding a newline |
| LET     | N/A    | Tokenized but not used (ignored). |
| IF      | IF (expr) THEN (expr) | If the expression evaluates to 1 (True), jump to the line evaluated by the second expr. |
| THEN    | N/A | Part of IF |
| FOR     | FOR (ident) = (expr) TO (expr) \[STEP (expr)\] | Set the ident to first expr, loop until end expr, optionally step by final expr per loop. |
| TO      | N/A | Part of FOR, PEEK, and POKE |
| STEP    | N/A | Part of FOR |
| GOTO    | GOTO (expr) | Jump to line evaluated by expr |
| PEEK    | PEEK (expr) TO (ident) | Store the value in memory at expr into ident |
| POKE    | POKE (ident) TO (expr) | Store the value of ident in memory at expr |
| GOSUB   | N/A | Tokenized but not used (ignored). |
| RETURN  | N/A | Tokenized but not used (ignored). |
| END     | END | Terminates interpretation immediately |
| REM     | REM ... | Remarks are completely ignored |

## Variables

All variables are either a number, string, or array.
Variables are case-sensitive, i.e. "X" is not the same as "x".
Variables are not strongly typed, so their type can be re-assigned:

```basic
10 REM "X will be the string Hello"
20 X = "Hello"
30 REM "X will be re-assigned to a number (the length of the string it previously held, 5)"
40 X = LEN(X)
```

## Arrays

Arrays can be defined with the `ARRAY(number)` function. The length of the array is the number provided
to the function. Arrays cannot grow/shrink, but adding two arrays will concatenate them into a single
larger array:

```basic
10 REM "X is an array with 5 elements (all initialized to 0)"
20 X = ARRAY(5)
30 REM "Arrays cannot be resized once created, but adding two together creates a new larger array:"
40 Y = X + ARRAY(15)
50 REM "Y is an array with space for 20 elements (5 from X, 15 from the anonymous array)"
60 PRINT "Y has room for ", LEN(Y), " elements."
70 REM "Arrays can hold any type in each element, including themselves:"
80 Y[0] = Y
90 PRINT Y[0][0][0]
```

## Functions

| Function | Argument type   | Description |
|----------|-----------------|-------------|
| ABS      | number          | Absolute value of number |
| LEN      | string or array | Length of argument|
| CHR      | number          | Number to ASCII|
| INT      | string          | Convert first character of string to number|
| LCASE    | string          | Convert string to lowercase|
| UCASE    | string          | Convert string to uppercase|
| ARRAY    | number          | Return an empty array of specified length|
| TYPE     | any             | Return type name of argument ("number", "string", "array")|
| SIN      | number          | sine(number)|
| COS      | number          | cosine(number)|
| TAN      | number          | tangent(number)|
| SQRT     | number          | square root(number)|
| FLOOR    | number          | Round down number to nearest integer|
| CEIL     | number          | Round up number to nearest integer|
| DEG      | number          | Convert radians to degrees|
| RAD      | number          | Convert degrees to radians|
