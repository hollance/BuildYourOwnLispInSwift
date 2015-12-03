# Build Your Own LISP in Swift

This is Daniel Holden's excellent [Build Your Own LISP](http://buildyourownlisp.com) tutorial converted to Swift 2.0 (Xcode 7.1 and up).

## Usage

To run Lispy as a REPL type the following from a terminal:

	$ swift Lispy.swift

Now you can type all kinds of LISP-ish stuff behind the `lispy>` prompt. For example,

	lispy> (+ 1 2 3)

will add up the values 1, 2, and 3, and produce the output `6`. Yay!

You can also leave off the parentheses:

	lispy> + 1 2 3
	
A useful command is `help`:
	
	lispy> help {env}
	
This shows the contents of the current "environment", which lists all the available functions with a quick summary of what they do.

You can type full LISP programs into the REPL:

	lispy> fun {factorial n} { if (== n 0) { 1 } { (* n (factorial (- n 1))) } }
	lispy> factorial 5
	120

It may be a bit easier to read across multiple lines. To indicate to the REPL that you're continuing on the next line, end each line with a semicolon:

	lispy> fun {factorial n} { ;
	  if (== n 0) ;
	    { 1 } ;
	    { (* n (factorial (- n 1))) } ;
	  }
	lispy> factorial 5
	120

You can also import a source file into the REPL:

	> load "test.lispy"

This evaluates all the expressions in that file, but unlike when you enter code manually it does not print the results. You have to use the `print` function for that.

To quit the REPL, press Ctrl+C.

To run Lispy on a source file without using the REPL, type from the terminal:

	$ swift Lispy.swift test.lispy

Note: Unlike in the REPL, all the expressions in this source file must be surrounded by `( )` parentheses, otherwise the parser won't know where one expression ends and the next begins.

For more speed, you can compile Lispy.swift using the following command:

	swiftc -sdk $(xcrun --show-sdk-path --sdk macosx) -O -o Lispy Lispy.swift

## The language

This is a simple LISP-like language. It is dynamically typed, meaning that variables do not have a specific datatype -- a variable is just a name that you've associated with some value. Only values have a type.

Data objects can have the following types:

- error
- integer number
- text string
- symbol
- S-Expression
- Q-Expression
- built-in function
- user-defined lambda function

### Symbols

A *symbol* is an identifier. You use these to give names to values.

Symbols may include the characters `a-z A-Z 0-9`, the underscore `_`, the arithmetic operator characters `+ - * /`, the backslash character `\`, the comparison operator characters `= < > !`, or an ampersand `&`.

To give a name to a value, you use `def`:

	lispy> def {x} 100
	lispy> x
	100

Or more than one variable at a time:

	lispy> def {y z} 200 300
	lispy> y
	200
	lispy> z
	300

The variables are now part of the *environment*, which stores the mapping of names to values.

To see the contents of the current environment:

	lispy> help {env}
	
The `help` function is also useful for viewing information on a specific function:

	lispy> help {def}

By the way, you can create your own help documentation using the `doc` command:

	lispy> doc {my-func} "My awesome function"
	lispy> help {my-func}

`def` always puts the name into the global environment. Each function also has its own local environment. To put a name into that local environment, you use `=`.

A silly example:

	lispy> def {some-func} (\ {x} { do (= {y} (+ x 1)) (help {env}) })

This defines a new lambda and gives it the name `some-func`. When you call it with some value, it creates a new local variable `y` that only exists for the duration of that function.

	lispy> some-func 100
	----------Environment (local)-----------
	Variables:
	x: Integer = 100
	y: Integer = 101
	----------------------------------------
	lispy> y
	Error: Unbound symbol 'y'

After the function finishes, the local environment is destroyed and `x` and `y` no longer exist.

`def` is quite powerful. A cool example:

	lispy> def {arglist} {a b c}  
	lispy> arglist  
	{a b c}  
	lispy> def arglist 1 2 3
	lispy> a
	1
	lispy> b
	2
	lispy> c
	3

You can assign a name to any kind of value, even to a Q-Expression or a function. Example:

	lispy> def {p} +  
	lispy> p 1 2  
	3

When you use an S-Expression, it is evaluated first and then the result is assigned to the value:

	lispy> def {x} 100
	lispy> def {y} (+ 1 x)  
	lispy> y
	101
	lispy> def {x} 200
	lispy> y
	101                  did not change!

### S-Expressions

An *S-Expression* contains executable code. It looks like this:

	(+ 1 2 3)
	
The `( )` parentheses are what makes this an S-Expression.

The first element should be a symbol that represents a function. When the interpreter evaluates an S-Expression, it applies that function to the rest of the elements.

Note: A big difference with traditional LISP is that these S-Expression lists are not built from *cons cells* but are regular dynamic arrays.

### Q-Expressions

A *Q-Expression* is a list of data. It looks like this:

	{1 2 3}

The `{ }` braces distinguish this kind of list from an S-Expression. When a Q-Expression is evaluated nothing happens, it's just data.

In traditional LISPs, you'd use `QUOTE` or `'` to convert an S-Expression (code) into a Q-Expression (data), but here you use `{ ... }` braces instead.

Q-Expressions allow you to write the following:

	lispy> def {x} 123

This assigns the name `x` to the value `123`. However, if you write it without the curly braces,

	lispy> def x 123

then it no longer means, "assign the value `123` to the name `x`" but "assign the value `123` to the name *from the value* of `x`. This might work, or it might not. It  depends on whether the name `x` exists already and whether it refers to another symbol. For example:

	lispy> def {x} {y}
	{y}
	lispy> def x 123           this is really def {y} 123
	()
	lispy> y
	123

The function `eval` turns a Q-Expression into an S-Expression and evaluates it:

	lispy> (+ 1 2 3)           this is an S-Expression
	6                          it is evaluated
	
	lispy> {+ 1 2 3}           this is a Q-Expression
	{+ 1 2 3}                  it does nothing
	
	lispy> eval {+ 1 2 3}      using eval 
	6

The trick in writing proper Lispy programs is to make sure you use S-Expressions and Q-Expressions in the right places.

### Built-in functions

The language comes with a minimal set of built-in functions that can perform basic tasks on Q-Expressions and other values.

You can do arithmetic on numeric values using `+`, `-`, `*`, `/`.

**list** Creates a new Q-Expression from one or more values.
	
	lispy> list 1 2 3 4
	{1 2 3 4}
	
	lispy> list (list 1 2 3) (list 4 5 6)
	{{1 2 3} {4 5 6}}
	
**head** Returns the first element from a Q-Expression.

	lispy> head {1 2 3}
	{1}

Note: the result is still a Q-Expression, which may not be what you want. If a Q- or S-Expression only has one element, calling `eval` returns just that element. So to pull the value out, `eval` the result:

	lispy> eval (head {1 2 3})
	1

**tail** Returns a Q-Expression with the first element removed.
	
	lispy> tail {1 2 3}
	{2 3}

**join** Combines two or more Q-Expressions.

	lispy> join {1} {2 3}
	{1 2 3}
	
**eval** Takes a Q-Expression and evaluates it as if it were a S-Expression.

	lispy> eval {head (list 1 2 3 4)}
	{1}

	lispy> eval (tail {tail tail {5 6 7}})
	{6 7}

	lispy> eval (head {(+ 1 2) (+ 10 20)})
	3

This is what allows you to treat data as code and what makes LISP awesome.

**print** Prints a value to stdout.

	lispy> print "hello\nworld!"
	hello
	world!

You can print anything, not just strings.

**error** Generates an error value with a message.

	lispy> error "Houston, we've got a problem!"

**if** Decisions, decisions... `if` lets you make them.

	lispy> if (> x 10) { print "yep" } { print "nope" }

The code from the first Q-Expression is evaluated when the condition is true; the code from the second Q-Expression otherwise.

You can compare numbers using `<`, `<=`, `>`, `>=`, `==`, `!=`. These return `1` (true) or `0` false. In general, the value `0` evaluates as false and anything that is not `0` evaluates as true.

There are no looping constructs in LISP. To make a loop, you need to use recursion.

### Lambdas

Ah, the good stuff! A lambda is like a closure in Swift.

To create a lambda expression, you use `\` because λ is too hard to type:

	lispy> \ {x y} {+ x y}

Here, `{x y}` are the formal arguments, and `{+ x y}` is the body of the function.

Calling the lambda function:

	lispy> (\ {x y} {+ x y}) 10 20
	30

They are a bit useless by themselves, so here's how you'd give the lambda a name:

	lispy> def {add-together} (\ {x y} {+ x y})
	lispy> add-together 10 20
	30

The standard library comes with a shortcut notation for defining your own functions:

	lispy> fun {add-together x y} {+ x y}

This does the exact same thing as above but saves some typing.

Most of your LISP coding will involve writing your own functions in this manner. 

A function always returns some value. If you have nothing to return, then it's customary to return the empty list `()` or `{}` (or the synonym `nil`).

Lambdas can take a variable number of arguments, using the syntax `{x & xs}`, where `xs` is a list containing the additional arguments.

	lispy> def {my-join} (\ {x & xs} {join x xs})
	lispy> my-join {a}
	{a}
	lispy> my-join {a} {b}
	{a {b}}
	lispy> my-join {a} {b c}
	{a {b c}}
	lispy> my-join {a} {b} {c}
	{a {b} {c}}

### Cool tricks with functions

You don't always need to specify values for all arguments of a function. This is called "partial application". 

This is how you'd normally create and call a function:

	lispy> fun {add-mul x y} {+ x (* x y)}
	lispy> add-mul 10 20
	210
	
Fair enough. But what if you do this:

	lispy> add-mul 10
	(\ {y} {+ x (* x y)}) x=10
	
Because `add-mul` expects two arguments and you only specified one, what you get back is a new lambda. This new lambda still expects the parameter `y`.

Remember how functions have their own local environment? For a partially applied function, that environment contains the values of their arguments. In this case, the new lambda knows that `x` is `10` already.

What's the use of this? Well, it allows you to do something like:
	
	lispy> def {add-mul-ten} (add-mul 10)
	lispy> add-mul-ten 50
	510

So you can create new functions from existing functions by only partially evaluating them. Functional programming boffins love it!

Another hip thing is currying. Yum! The `+` function doesn't normally take a list and you'd call it like so:

	lispy> + 5 6 7

But `curry` fixes that:
	
	lispy> curry + {5 6 7}

The other way around works too, when a function takes a list as input but you wish to call it using variable arguments:
	
	lispy> uncurry head 5 6 7

## The standard library

A language is pretty useless without a good library of functions. Besides the handful of built-in functions listed above, Lispy comes with a very basic library. These functions are defined in LISP itself. You can see them in [stdlib.lispy](stdlib.lispy). This source file is imported automatically when you start Lispy.

Some highlights:

**reverse** Changes the order of the elements in a list.

	lispy> reverse {1 2 3 4}
	{4 3 2 1}
	
**map** Applies a function to all items in a list.

	lispy> map (\ {x} {+ x 10}) {5 2 11}
	{15 12 21}

**filter** Removes items from a list that do not match the given condition.

	lispy> filter (\ {x} {> x 2}) {5 2 11 -7 8 1}
	{5 11 8}

**foldl** Fold left is like `reduce` in Swift.

	lispy> foldl (\ {a x} {+ a x}) 0 {1 2 3 4}
	10
	
Or simply:

	lispy> foldl + 0 {1 2 3 4}
	10

**select** This works like Swift's `switch` statement.

	(fun {month-day-suffix i} {
	  select
		{(== i 0)  "st"}
		{(== i 1)  "nd"}
		{(== i 3)  "rd"}
		{otherwise "th"}
	})

**case** Like Objective-C's `switch` statement. ;-)

	(fun {day-name x} {
	  case x
		{0 "Monday"}
		{1 "Tuesday"}
		{2 "Wednesday"}
		{3 "Thursday"}
		{4 "Friday"}
		{5 "Saturday"}
		{6 "Sunday"}
	})

**do** Perform a sequence of commands.

	lispy> do (print "hello") (print "world")

## Future improvements

- The parser isn't very good. The original tutorial uses parser combinators, which would be a fun thing to play with.

- The original tutorial allows comments in the source files (starting with `;`), but my parser does not support this currently.

- The built-in functions use a lot of `guard` statements to verify that input is correct. This is necessary because the language is dynamically typed. But it would be nice to write some Swift "macros" to make this part of the code a bit more readable.

- Use proper *cons cells* to make lists like a true LISP.

- The REPL isn't very user-friendly. You can't use the arrow keys to go back. Using semicolons to type on multiple lines is meh.

- The REPL doesn't require you to put `( )` around everything you write. That is convenient but also a bit misleading since source files do require it. If we were to require `( )` then supporting multiple lines becomes easier: the input isn't done until the last `)` matches up with the first `(`.

- Add a `Value.Real` type to support floating-point values. When doing arithmetic, integers should be promoted to Reals if necessary.

- Add a `Value.Boolean` type?

- Make `Value` conform to `Comparable` instead of just `Equatable`, to simplify the code for the comparison operators.

- You cannot evaluate functions that take no parameters. This just prints out the name of the function. I don't know if this is a big deal, you could just make it a variable instead.

- It is not particularly efficient. :-D

## Credits

This is pretty much a straight port from Daniel Holden's [Build Your Own LISP](http://buildyourownlisp.com) code, with some Swift goodness thrown in and a few modifications of my own. Many of the examples in this document are taken from his excellent tutorial. [Go read it now!](http://buildyourownlisp.com)

Licensed under [Creative Commons Attribution-NonCommercial-ShareAlike 3.0](http://creativecommons.org/licenses/by-nc-sa/3.0/)
