Shortcomings (that I know about):

* Extremely fragile interpreter. I didn't even try to make this robust, so malformed BASIC will most likely mimic g++ error messages.
* Order of operations simply does not exist. To get correct math evaluation, use a copious amount of parentheses:
	2 + 3 * 2 incorrectly evaluates to 8, but 2 * (3 + 2) correctly produces 10.
* Very limited feature set. The goal was to produce a minimal functional BASIC interpreter for use on the Pi Pico.
* Arrays don't exist, use strings (INT, CHR, LEN, the concatenation operator ',', and indexing via []: "Hello"[0] == "H")
* Unary negation is unbelievably beyond my comprehension for some reason, so if you want negative literals, do (0 - number): -5 == (0 - 5)
