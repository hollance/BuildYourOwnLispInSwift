import Foundation

/*
  A conversion of www.buildyourownlisp.com into Swift.
*/

// MARK: - Values

/*
  Everything in our LISP is about manipulating values.

  This version of LISP is dynamically typed, meaning that variables do not have
  a specific type, they are just names. Only values have a type.

  The Value enum describes a value, its type, and the data it holds.
*/

typealias Builtin = (env: Environment, values: [Value]) -> Value

enum Value {
  // When an error has occurred, we create and return an Error value.
  case Error(message: String)

  // An integer number. Also used for boolean values, where 0 is false, != 0 is 
  // true. Currently there is no support for real numbers (i.e. Double).
  case Number(value: Int)

  // A text string.
  case Text(value: String)

  // A symbol is a name that you can bind to some other value. This is what you
  // use to create variables and named fuctions.
  case Symbol(name: String)

  // An S-Expression is a piece of executable code. Example: (+ 1 2). Only code
  // in between ( ) parentheses is evaluated.
  case SExpression(values: [Value])

  // A Q-Expression is a list of literal data items. Example: {1 2 3}. The curly
  // brackets turn code into data; the 'eval' function turns a Q-Expression back
  // into code.
  case QExpression(values: [Value])

  // The built-in functions are the primitive operations of the language. These
  // are too low-level to express in LISP itself.
  case BuiltinFunction(name: String, code: Builtin)

  // A lambda is a user-defined function. Example: \ {x y} {+ x y}. Usually you
  // bind this to a name with 'def' so that you can use it more than once.
  //
  // The formal parameters, {x y} in the example, are stored as a string array,
  // ["x", "y"]. The body, {+ x y}, is stored as an array of Values. This is 
  // more convenient than storing the original Q-Expressions, because we have
  // to convert those to arrays anyway. The body is turned into an S-Expression
  // when the function gets evaluated.
  //
  // The Environment object is needed for partial function application, because
  // it has the values of the parameters that have been filled in already.
  case Lambda(env: Environment, formals: [String], body: [Value])
}

// MARK: - Creating values

/*
  Normally you'd first parse LISP code into an AST (Abstract Syntax Tree) and
  then evaluate that tree. However, you can also create such an AST directly in
  Swift by writing:

    // Create the AST for the S-Expression (+ 123 456)
    let v1 = Value.Symbol(name: "+")
    let v2 = Value.Number(value: "123")
    let v3 = Value.Number(value: "456")
    let v4 = Value.SExpression(values: [v1, v2, v3])
    // And evaluate it...
    let result = v4.eval(env)

  However, thanks to the below LiteralConvertible extensions, you can simply
  write this as:

    let v = Value.SExpression(values: ["+", 123, 456])
    let result = v.eval(env)

  Swift automatically figures out that "+" is a Symbol and that 123 and 456 are
  Number values.

  It's not super useful, because you almost never need to create an AST by hand
  but it's nice for when you want to test something without using the parser.
*/

// Allows you to write true instead of Value.Number(1); false becomes Value(0).
extension Value: BooleanLiteralConvertible {
  init(booleanLiteral value: Bool) {
    self = .Number(value: value ? 1 : 0)
  }
}

// Allows you to write 123 instead of Value.Number(123).
extension Value: IntegerLiteralConvertible {
  typealias IntegerLiteralType = Int
  init(integerLiteral value: IntegerLiteralType) {
    self = .Number(value: value)
  }
}

// Allows you to write "A" instead of Value.Symbol("A").
extension Value: StringLiteralConvertible {
  typealias StringLiteralType = String
  init(stringLiteral value: StringLiteralType) {
    self = .Symbol(name: value)
  }

  typealias ExtendedGraphemeClusterLiteralType = StringLiteralType
  init(extendedGraphemeClusterLiteral value: ExtendedGraphemeClusterLiteralType) {
    self = .Symbol(name: value)
  }

  typealias UnicodeScalarLiteralType = StringLiteralType
  init(unicodeScalarLiteral value: UnicodeScalarLiteralType) {
    self = .Symbol(name: value)
  }
}

// Turns an array of values into a Q-Expression.
extension Value: ArrayLiteralConvertible {
  typealias Element = Value
  init(arrayLiteral elements: Element...) {
    self = .QExpression(values: elements)
  }
}

// Allows you to write nil to create an empty Q-Expression.
extension Value: NilLiteralConvertible {
  init(nilLiteral: ()) {
    self = .QExpression(values: [])
  }
}

extension Value {
  // Convenience method for returning an empty S-Expression.
  static func empty() -> Value {
    return .SExpression(values: [])
  }
}

// MARK: - Comparing values

/*
  Values are Equatable, because we must be able to compare them using the '=='
  operator, both in Swift as in the LISP language itself.
*/

extension Value: Equatable {
}

func ==(lhs: Value, rhs: Value) -> Bool {
  switch (lhs, rhs) {
  case (.Error(let message1), .Error(let message2)):
    return message1 == message2
  case (.Number(let value1), .Number(let value2)):
    return value1 == value2
  case (.Text(let value1), .Text(let value2)):
    return value1 == value2
  case (.Symbol(let name1), .Symbol(let name2)):
    return name1 == name2
  case (.SExpression(let values1), .SExpression(let values2)):
    return values1 == values2
  case (.QExpression(let values1), .QExpression(let values2)):
    return values1 == values2
  case (.BuiltinFunction(let name1, _), .BuiltinFunction(let name2, _)):
    return name1 == name2
  case (.Lambda(_, let formals1, let body1), .Lambda(_, let formals2, let body2)):
    return formals1 == formals2 && body1 == body2
  default:
    return false
  }
}

// MARK: - Printing values

/*
  The functions in this String extension add and remove escape codes such as 
  \n and \t. They are quick-and-dirty placeholders for a better implementation.
*/

extension String {
  // Adds escape codes for unprintable characters. Used when printing in the
  // REPL and for showing help. In those cases we want to show the text with
  // unprintable characters represented by escape codes, just as you'd write
  // a string literal in source code.
  func escaped() -> String {
    var out = ""
    for c in self.characters {
      switch c {
      case "\n": out += "\\n"
      case "\t": out += "\\t"
      case "\\": out += "\\\\"
      default:   out += "\(c)"
      }
    }
    return out
  }

  // Turns "\n" "\t" and so on into actual characters. Used during parsing.
  func unescaped() -> String {
    var out = ""
    var i = startIndex
    while i < endIndex {
      let c = self[i]
      i = i.successor()
      if c == "\\" && i < endIndex {
        switch self[i] {
        case "n":  out += "\n"
        case "t":  out += "\t"
        case "\\": out += "\\"
        default:   out += "\(self[i])"
        }
        i = i.successor()
      } else {
        out += "\(c)"
      }
    }
    return out
  }
}

/*
  We often need to print Value objects.

  The REPL shows the result of every expression it evaluates, which again is a
  Value. It uses the debugDescription for that. (This only happens in the REPL;
  we don't print the evaluation results when executing a source file.)

  The debug description is also used to print help information about named
  objects and the current environment.

  The regular, non-debug description is used with the 'print' built-in function.
  It shows the real value of the object, without any extra fluff.
*/

extension Value: CustomStringConvertible, CustomDebugStringConvertible {
  var description: String {
    switch self {
    case Text(let value):
      return "\(value)"
    default:
      return debugDescription
    }
  }

  var debugDescription: String {
    switch self {
    case .Error(let message):
      return "Error: \(message)"
    case Number(let value):
      return "\(value)"
    case Text(let value):
      return "\"\(value.escaped())\""
    case Symbol(let name):
      return name
    case SExpression(let values):
      return "(" + listToString(values) + ")"
    case QExpression(let values):
      return "{" + listToString(values) + "}"
    case BuiltinFunction(let name, _):
      return "<\(name)>"
    case Lambda(let env, let formals, let body):
      var s = "(\\ {\(listToString(formals))} {\(listToString(body))})"

      // If this lambda is a partially applied function, then also print the
      // values of the parameters that have been filled in already.
      if !env.defs.isEmpty {
        for (k, v) in env.defs {
          s += " \(k)=\(v.debugDescription)"
        }
      }
      return s
    }
  }

  private func listToString(values: [String]) -> String {
    return values.joinWithSeparator(" ")
  }

  private func listToString(values: [Value]) -> String {
    return values.map({ $0.debugDescription }).joinWithSeparator(" ")
  }

  var typeName: String {
    switch self {
    case Error: return "Error"
    case Number: return "Number"
    case Text: return "String"
    case Symbol: return "Symbol"
    case SExpression: return "S-Expression"
    case QExpression: return "Q-Expression"
    case BuiltinFunction: return "Built-in Function"
    case Lambda: return "Lambda"
    }
  }
}

// MARK: - Environment

/*
  We often want to bind a value to a name, for example to make a variable or to
  turn an anonymous lambda into a reusable function.

  These names and their associated values are stored in the environment.

  When a LISP program tries to evaluate a symbol, it looks up that name in the
  environment and uses the associated value. It gives an Error value if the name
  is not found.

  There is one "global" environment, which exists for the duration of the LISP
  program. This contains definitions for all the built-in functions and those
  from the standard library. When you use the 'def' command, it adds a new name
  and value to this global environment.

  When a function or lambda is evaluated, it is given its own Environment object.
  This contains the values for the function's formal parameters, and any local
  names you defined with the '=' command. This "local" environment has a link to
  the global one through its parent property.

  A cool feature of this LISP is that you're allowed to invoke a function but
  not supply it all of its parameters, known as "partial function application".
  The result is a new Lambda value that has an Environment with the values for
  the parameters you already supplied.
*/

class Environment {
  private(set) var defs = [String: Value]()
  private(set) var docs = [String: String]()

  var parent: Environment?

  // Follows the parent references up until we get the global environment.
  func globalEnvironment() -> Environment {
    var env = self
    while case let parent? = env.parent { env = parent }
    return env
  }

  // Making a copy is necessary for partial function application and recursion,
  // because Environment is a reference type, not a value type.
  func copy() -> Environment {
    let e = Environment()
    e.defs = defs
    e.parent = parent
    return e
  }
}

// These methods add and retrieve values from the environment.
extension Environment {
  func get(name: String) -> Value {
    if let value = defs[name] {
      return value
    } else if let parent = parent {
      return parent.get(name)
    } else {
      return .Error(message: "Unbound symbol '\(name)'")
    }
  }

  func put(name name: String, value: Value) {
    defs[name] = value
  }
}

// The environment doesn't just store names and their values, but you can also
// add a documentation string for a name.
extension Environment {
  func getDoc(name: String) -> String {
    if let text = docs[name] {
      return text
    } else if let parent = parent {
      return parent.getDoc(name)
    } else {
      return ""
    }
  }

  func putDoc(name name: String, descr: String) {
    docs[name] = descr
  }
}

// This is used to print the current Environment with the 'help {env}' command.
extension Environment: CustomDebugStringConvertible {
  var debugDescription: String {
    var s = ""
    if parent == nil {
      s += "----------Environment (global)----------\n"
    } else {
      s += "----------Environment (local)-----------\n"
    }

    var builtins = [(String, Value)]()
    var lambdas = [(String, Value)]()
    var variables = [(String, Value)]()

    for name in defs.keys.sort(<) {
      let value = defs[name]!
      switch value {
      case .BuiltinFunction:
        builtins.append((name, value))
      case .Lambda:
        lambdas.append((name, value))
      default:
        variables.append((name, value))
      }
    }

    s += "Built-in functions:\n"
    for (name, _) in builtins {
      s += "\(name)"
      if let descr = docs[name] {
        s += "\n   \(descr)"
      }
      s += "\n"
    }

    s += "\nUser-defined lambdas:\n"
    for (name, value) in lambdas {
      s += "\(name)"
      if let descr = docs[name] {
        s += "\n   \(descr)"
      }
      s += "\n   \(value.debugDescription)\n"
    }

    s += "\nVariables:\n"
    for (name, value) in variables {
      s += "\(name): \(value.typeName) = \(value.debugDescription)"
      if let descr = docs[name] {
        s += ", \(descr)"
      }
      s += "\n"
    }

    return s + "----------------------------------------"
  }
}

// MARK: - Evaluating

/*
  After having parsed the abstract syntax tree (AST) from a LISP source file or
  the REPL, we need to evaluate it.

  Evaluation means that we look at each Value in turn, process it somehow, and
  get a new Value object as a result. Most values simply evaluate to themselves:
  a number always stays a number, a string always stays a string.

  The most complicated thing to evaluate is the S-Expression. If an S-Expr has
  more than one item, the first is considered to be a function (either built-in
  or a user-defined lambda) that gets applied to the rest of the items.
*/

extension Value {
  func eval(env: Environment) -> Value {
    // Uncomment the next line to see exactly what happens...
    //print("eval \(self.debugDescription)")

    switch self {
    case .Symbol(let name):
      return env.get(name)
    case .SExpression(let values):
      return evalList(env, values)
    default:
      return self  // pass along literally without evaluating
    }
  }

  // Evaluate the values inside the S-Expression recursively.
  private func evalList(env: Environment, var _ values: [Value]) -> Value {
    // Evaluate children. If any of them are symbols, they will be converted 
    // into the associated value from the environment, such as a function, a 
    // number, or a Q-Expression.
    for var i = 0; i < values.count; ++i {
      values[i] = values[i].eval(env)
    }

    // If any children are errors, return the first error we encounter.
    for value in values {
      if case .Error = value { return value }
    }

    // An empty expression has an empty result.
    if values.count == 0 { return Value.empty() }

    // Single expression; simply return the first (and only) child.
    // This has the effect of "unwrapping" the object from the list.
    if values.count == 1 { return values[0] }

    // Ensure first value is a function, then call it on the remaining values.
    let first = values.removeFirst()
    switch first {
    case .BuiltinFunction(_, let code):
      return code(env: env, values: values)
    case .Lambda(let localEnv, let formals, let body):
      return evalLambda(env, localEnv.copy(), formals, values, body)
    default:
      return .Error(message: "Expected function, got \(first)")
    }
  }

  // First, this binds the lambda's formal argument with the supplied values.
  // If the lambda's argument list contains a '&' symbol, then it accepts a
  // variable number of arguments and we have to do some extra work. Once all
  // the arguments have values, we turn the function body into an S-Expression
  // and evaluate it.
  private func evalLambda(parentEnv: Environment, _ localEnv: Environment, var _ formals: [String], var _ args: [Value], _ body: [Value]) -> Value {
    let given = args.count
    let expected = formals.count

    while args.count > 0 {
      // Have we ran out of formal arguments to bind?
      if formals.count == 0 {
        return .Error(message: "Expected \(expected) arguments, got \(given)")
      }

      // Look at the next symbol from the formals.
      let sym = formals.removeFirst()

      // Special case to deal with '&' for variable-argument lists.
      if sym == "&" {
        if formals.count != 1 {
          return .Error(message: "Expected a single symbol following '&'")
        }
        // The next formal should be bound to the remaining arguments.
        let nextSym = formals.removeFirst()
        localEnv.put(name: nextSym, value: .QExpression(values: args))
        break
      }

      // Bind the next arg to this name in the function's local environment.
      localEnv.put(name: sym, value: args.removeFirst())
    }

    // If a '&' remains in formal list, bind it to an empty Q-Expression.
    if formals.count > 0 && formals[0] == "&" {
      if formals.count != 2 {
        return .Error(message: "Expected a single symbol following '&'")
      }
      // Delete the '&' and associate the final symbol with an empty list.
      formals.removeFirst()
      let sym = formals.removeFirst()
      localEnv.put(name: sym, value: [])
    }

    // If all formals have been bound, evaluate the function body.
    if formals.count == 0 {
      localEnv.parent = parentEnv
      return Value.SExpression(values: body).eval(localEnv)
    } else {
      // Otherwise return partially evaluated function.
      return .Lambda(env: localEnv, formals: formals, body: body)
    }
  }
}

// MARK: - Built-in functions

/*
  As much as possible of the language is implemented in LISP itself, in the
  standard library (stdlib.lispy). However, some primitives must be provided
  as built-in functions.
*/

let builtin_list: Builtin = { _, values in .QExpression(values: values) }

let builtin_eval: Builtin = { env, values in
  guard values.count == 1 else {
    return .Error(message: "'eval' expected 1 argument, got \(values.count)")
  }
  guard case .QExpression(let qvalues) = values[0] else {
    return .Error(message: "'eval' expected Q-Expression, got \(values[0])")
  }
  return Value.SExpression(values: qvalues).eval(env)
}

let builtin_head: Builtin = { _, values in
  guard values.count == 1 else {
    return .Error(message: "'head' expected 1 argument, got \(values.count)")
  }
  guard case .QExpression(let qvalues) = values[0] else {
    return .Error(message: "'head' expected Q-Expression, got \(values[0])")
  }
  if qvalues.count == 0 {
    return .Error(message: "'head' expected non-empty Q-Expression, got {}")
  }
  return .QExpression(values: [qvalues[0]])
}

let builtin_tail: Builtin = { env, values in
  guard values.count == 1 else {
    return .Error(message: "'tail' expected 1 argument, got \(values.count)")
  }
  guard case .QExpression(var qvalues) = values[0] else {
    return .Error(message: "'tail' expected Q-Expression, got \(values[0])")
  }
  if qvalues.count == 0 {
    return .Error(message: "'tail' expected non-empty Q-Expression, got {}")
  }
  qvalues.removeFirst()
  return .QExpression(values: qvalues)
}

let builtin_join: Builtin = { env, values in
  var allValues = [Value]()
  for value in values {
    if case .QExpression(let qvalues) = value {
      allValues += qvalues
    } else {
      return .Error(message: "'join' expected Q-Expression, got \(value)")
    }
  }
  return .QExpression(values: allValues)
}

/*
  The following are mathematical operators. These only work on Number values.
*/

typealias BinaryOperator = (Value, Value) -> Value

func curry(op: (Int, Int) -> Int)(_ lhs: Value, _ rhs: Value) -> Value {
  guard case .Number(let x) = lhs else {
    return .Error(message: "Expected number, got \(lhs)")
  }
  guard case .Number(let y) = rhs else {
    return .Error(message: "Expected number, got \(rhs)")
  }
  return .Number(value: op(x, y))
}

func performOnList(env: Environment, var _ values: [Value], _ op: BinaryOperator) -> Value {
  var x = values[0]
  for var i = 1; i < values.count; ++i {
    x = op(x, values[i])
    if case .Error = x { return x }
  }
  return x
}

let builtin_add: Builtin = { env, values in
  performOnList(env, values, curry(+))
}

let builtin_subtract: Builtin = { env, values in
  if values.count == 1 {
    if case .Number(let x) = values[0] {  // unary negation
      return .Number(value: -x)
    } else {
      return .Error(message: "Expected number, got \(values[0])")
    }
  } else {
    return performOnList(env, values, curry(-))
  }
}

let builtin_multiply: Builtin = { env, values in
  performOnList(env, values, curry(*))
}

let builtin_divide: Builtin = { env, values in
  performOnList(env, values) { lhs, rhs in
    if case .Number(let y) = rhs where y == 0 {
      return .Error(message: "Division by zero")
    } else {
      return curry(/)(lhs, rhs)
    }
  }
}

/*
  The following are comparison operators. These only work on Number values.
*/

func curry(op: (Int, Int) -> Bool)(_ lhs: Value, _ rhs: Value) -> Value {
  guard case .Number(let x) = lhs else {
    return .Error(message: "Expected number, got \(lhs)")
  }
  guard case .Number(let y) = rhs else {
    return .Error(message: "Expected number, got \(rhs)")
  }
  return .Number(value: op(x, y) ? 1 : 0)
}

func comparison(env: Environment, var _ values: [Value], _ op: BinaryOperator) -> Value {
  if values.count == 2 {
    return op(values[0], values[1])
  } else {
    return .Error(message: "Comparison expected 2 arguments, got \(values.count)")
  }
}

let builtin_gt: Builtin = { env, values in
  return comparison(env, values, curry(>))
}

let builtin_lt: Builtin = { env, values in
  return comparison(env, values, curry(<))
}

let builtin_ge: Builtin = { env, values in
  return comparison(env, values, curry(>=))
}

let builtin_le: Builtin = { env, values in
  return comparison(env, values, curry(<=))
}

let builtin_eq: Builtin = { env, values in
  if values.count == 2 {
    return .Number(value: values[0] == values[1] ? 1 : 0)
  } else {
    return .Error(message: "'==' expected 1 arguments, got \(values.count)")
  }
}

let builtin_ne: Builtin = { env, values in
  if values.count == 2 {
    return .Number(value: values[0] != values[1] ? 1 : 0)
  } else {
    return .Error(message: "'!=' expected 2 arguments, got \(values.count)")
  }
}

let builtin_if: Builtin = { env, values in
  guard values.count == 3 else {
    return .Error(message: "'if' expected 3 arguments, got \(values.count)")
  }
  guard case .Number(let cond) = values[0] else {
    return .Error(message: "'if' expected number, got \(values[0])")
  }
  guard case .QExpression(var qvalues1) = values[1] else {
    return .Error(message: "'if' expected Q-Expression, got \(values[1])")
  }
  guard case .QExpression(var qvalues2) = values[2] else {
    return .Error(message: "'if' expected Q-Expression, got \(values[2])")
  }

  // If condition is true, evaluate first expression, otherwise second.
  if cond != 0 {
    return Value.SExpression(values: qvalues1).eval(env)
  } else {
    return Value.SExpression(values: qvalues2).eval(env)
  }
}

/*
  Functions for creating variables and functions.
*/

func bindVariable(env: Environment, _ values: [Value]) -> Value {
  guard case .QExpression(let qvalues) = values[0] else {
    return .Error(message: "Expected Q-Expression, got \(values[0])")
  }

  // Ensure all values from the Q-Expression are symbols.
  var symbols = [String]()
  for value in qvalues {
    if case .Symbol(let name) = value {
      symbols.append(name)
    } else {
      return .Error(message: "Expected symbol, got \(value)")
    }
  }

  // Check correct number of symbols and values.
  if symbols.count != values.count - 1 {
    return .Error(message: "Found \(symbols.count) symbols but \(values.count - 1) values")
  }

  // Put the symbols and their associated values into the environment.
  for (i, symbol) in symbols.enumerate() {
    env.put(name: symbol, value: values[i + 1])
  }

  return Value.empty()
}

let builtin_def: Builtin = { env, values in
  return bindVariable(env.globalEnvironment(), values)
}

let builtin_put: Builtin = { env, values in
  return bindVariable(env, values)
}

let builtin_lambda: Builtin = { env, values in
  guard values.count == 2 else {
    return .Error(message: "'\\' expected 2 arguments, got \(values.count)")
  }
  guard case .QExpression(var formalsValues) = values[0] else {
    return .Error(message: "'\\' expected Q-Expression, got \(values[0])")
  }
  guard case .QExpression(var bodyValues) = values[1] else {
    return .Error(message: "'\\' expected Q-Expression, got \(values[1])")
  }

  // Check that the first Q-Expression contains only symbols.
  var symbols = [String]()
  for value in formalsValues {
    if case .Symbol(let name) = value {
      symbols.append(name)
    } else {
      return .Error(message: "Expected symbol, got \(value)")
    }
  }

  return .Lambda(env: Environment(), formals: symbols, body: bodyValues)
}

/*
  I/O functions and miscellaneous.
*/

let builtin_print: Builtin = { env, values in
  for value in values {
    print(value, terminator: " ")
  }
  print("")
  return Value.empty()
}

let builtin_error: Builtin = { env, values in
  guard values.count == 1 else {
    return .Error(message: "'error' expected 1 argument, got \(values.count)")
  }
  guard case .Text(var message) = values[0] else {
    return .Error(message: "'error' expected string, got \(values[0])")
  }
  return .Error(message: message)
}

let builtin_doc: Builtin = { env, values in
  guard values.count == 2 else {
    return .Error(message: "'doc' expected 2 arguments, got \(values.count)")
  }
  guard case .QExpression(var qvalues) = values[0] else {
    return .Error(message: "'doc' expected Q-Expression, got \(values[0])")
  }
  guard case .Text(let descr) = values[1] else {
    return .Error(message: "'doc' expected number, got \(values[1])")
  }
  guard qvalues.count == 1 else {
    return .Error(message: "'doc' expected Q-Expression with 1 symbol")
  }
  guard case .Symbol(let name) = qvalues[0] else {
    return .Error(message: "'doc' expected symbol, got \(qvalues[0])")
  }
  env.putDoc(name: name, descr: descr)
  return Value.empty()
}

let builtin_help: Builtin = { env, values in
  guard values.count == 1 else {
    return .Error(message: "'help' expected 1 argument, got \(values.count)")
  }
  guard case .QExpression(var qvalues) = values[0] else {
    return .Error(message: "'help' expected Q-Expression, got \(values[0])")
  }
  guard qvalues.count == 1 else {
    return .Error(message: "'help' expected Q-Expression with 1 symbol")
  }
  guard case .Symbol(let name) = qvalues[0] else {
    return .Error(message: "'help' expected symbol, got \(qvalues[0])")
  }

  if name == "env" {  // special value
    debugPrint(env)
  } else {
    let descr = env.getDoc(name)
    if descr != "" {
      print(descr)
    } else {
      print("No documentation found for '\(name)'")
    }
  }
  return Value.empty()
}

// MARK: - Parser

/*
  This is a simplified version of the parser used in the original tutorial.
  It is not very smart or capable; any input it doesn't recognize simply gets
  ignored. But it works if you don't try to break it too hard. ;-)
*/

private func tokenizeString(s: String, inout _ i: String.Index) -> Value {
  var out = ""
  while i < s.endIndex {
    let c = s[i]
    i = i.successor()
    if c == "\"" {
      return .Text(value: out.unescaped())
    } else {
      out += "\(c)"
    }
  }
  return .Error(message: "Expected \"")
}

private func tokenizeAtom(s: String) -> Value {
  if let i = Int(s) {
    return .Number(value: i)
  } else {
    return .Symbol(name: s)
  }
}

private func tokenizeList(s: String, inout _ i: String.Index, _ type: String) -> Value {
  var token = ""
  var array = [Value]()

  while i < s.endIndex {
    let c = s[i]
    i = i.successor()

    // Symbol or number found.
    if (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") ||
       (c >= "0" && c <= "9") || c == "_" || c == "\\" ||
        c == "+" || c == "-" || c == "*" || c == "/" ||
        c == "=" || c == "<" || c == ">" || c == "!" || c == "&" {
      token += "\(c)"
    } else if c == "\"" {
      array.append(tokenizeString(s, &i))
    } else {
      if !token.isEmpty {
        array.append(tokenizeAtom(token))
        token = ""
      }
      // Open a new list.
      if c == "(" || c == "{" {
        array.append(tokenizeList(s, &i, "\(c)"))
      } else if c == ")" {
        if type == "(" {
          return .SExpression(values: array)
        } else {
          return .Error(message: "Unexpected )")
        }
      } else if c == "}" {
        if type == "{" {
          return .QExpression(values: array)
        } else {
          return .Error(message: "Unexpected }")
        }
      }
    }
  }

  // Don't forget the very last token.
  if !token.isEmpty {
    array.append(tokenizeAtom(token))
  }

  if type == "(" {
    return .Error(message: "Expected )")
  } else if type == "{" {
    return .Error(message: "Expected }")
  } else if array.count == 1 {
    return array[0]
  } else {
    return .SExpression(values: array)
  }
}

// This is the function you'd call to parse a source file. In order to tell
// expressions apart from each other in the file, each must be wrapped in ( )
// parentheses. This function parses the first of those S-Expressions it finds.
// You repeatedly call this function until you reach the end of the file.
func parseFile(s: String, inout _ i: String.Index) -> Value? {
  while i < s.endIndex {
    let c = s[i]
    i = i.successor()
    if c == "(" {
      return tokenizeList(s, &i, "(")
    }
  }
  return nil
}

// This is the function you'd call to parse input from the REPL. On the REPL,
// expressions don't need to be surrounded by parentheses. We automatically
// put the thing into an S-Expression.
func parseREPL(s: String) -> Value {
  var i = s.startIndex
  return tokenizeList(s, &i, "")
}

// MARK: - Loading source files

/*
  This LISP interpreter can either be used interactively using a REPL, or it
  can load and execute one or more source files. On the REPL you can load and
  execute a source file using the 'load' command.

  Note: Executing a source file does not produce any output unless you 'print'
  it, or if there is an error.
*/

func importFile(env: Environment, _ filename: String) -> Value {
  do {
    let s = try String(contentsOfFile: filename, encoding: NSUTF8StringEncoding)
    var i = s.startIndex
    while i < s.endIndex {
      if let expr = parseFile(s, &i) {
        if case .Error(let message) = expr {
          print("Parse error: \(message)")
        } else {
          let result = expr.eval(env)
          if case .Error(let message) = result {
            print("Error: \(message)")
          }
        }
      }
    }
    return Value.empty()
  } catch {
    return .Error(message: "Could not load \(filename), reason: \(error)")
  }
}

let builtin_load: Builtin = { env, values in
  guard values.count == 1 else {
    return .Error(message: "Function 'load' expected 1 argument, got \(values.count)")
  }
  guard case .Text(var filename) = values[0] else {
    return .Error(message: "Function 'load' expected string, got \(values[0])")
  }
  return importFile(env, filename)
}

// MARK: - REPL

/*
  The REPL simply reads a line of input, parses it, and then tries to evaluate
  the tree of Value objects. The REPL shows the result of every expression that
  gets evaluated.
*/

func readInput() -> String {
  let keyboard = NSFileHandle.fileHandleWithStandardInput()
  let inputData = keyboard.availableData
  let string = NSString(data: inputData, encoding: NSUTF8StringEncoding)!
  return string.stringByTrimmingCharactersInSet(NSCharacterSet.newlineCharacterSet())
}

func repl(env: Environment) {
  print("Lispy Version 0.16")
  print("Press Ctrl+C to Exit")

  var lines = ""
  while true {
    print("lispy> ", terminator: "")
    fflush(__stdoutp)
    let input = readInput()

    // Does the line end with a semicolon? Then keep listening for more input.
    if !input.isEmpty {
      let lastIndex = input.endIndex.predecessor()
      if input[lastIndex] == ";" {
        let s = input[input.startIndex ..< lastIndex]
        lines += "\(s)\n"
        continue
      }
    }

    lines += input
    let expr = parseREPL(lines)
    if case .Error(let message) = expr {
      print("Parse error: \(message)")
    } else {
      debugPrint(expr.eval(env))
    }
    lines = ""
  }
}

// MARK: - Initialization

/*
  This adds all the built-in functions to the global environment, and loads the
  standard library. Without these two steps, the language is useless.
*/

extension Environment {
  func addBuiltinFunction(name: String, _ descr: String = "", _ code: Builtin) {
    put(name: name, value: .BuiltinFunction(name: name, code: code))
    putDoc(name: name, descr: descr)
  }

  func addBuiltinFunctions() {
    let table = [
      ("eval", "Evaluate a Q-Expression. Usage: eval {q-expr}", builtin_eval),
      ("list", "Convert one or more values into a Q-Expression. Usage: list value1 value2...", builtin_list),
      ("head", "Return the first value from a Q-Expression. Usage: head {list}", builtin_head),
      ("tail", "Return a new Q-Expression with the first value removed. Usage: tail {list}", builtin_tail),
      ("join", "Combine one or more Q-Expressions into a new one. Usage: join {list} {list}...", builtin_join),

      ("+", "Add two numbers", builtin_add),
      ("-", "Subtract two numbers", builtin_subtract),
      ("*", "Multiply two numbers", builtin_multiply),
      ("/", "Divide two numbers", builtin_divide),

      (">", "Greater than", builtin_gt),
      ("<", "Less than", builtin_lt),
      (">=", "Greater than or equal to", builtin_ge),
      ("<=", "Less than or equal to", builtin_le),
      ("==", "Equals", builtin_eq),
      ("!=", "Not equals", builtin_ne),
      ("if", "Usage: if condition { true clause } { false clause }", builtin_if),

      ("def", "Bind names to one or more values in the global environment. Usage: def {symbol1 symbol2 ...} value1 value2...", builtin_def),
      ("=", "Bind names to one or more values in the current function's environment. Usage: = {symbol1 symbol2 ...} value1 value2...", builtin_put),

      ("\\", "Create a lambda. Usage: \\ {parameter names} {function body}", builtin_lambda),

      ("print", "Print a value to stdout. Usage: print value", builtin_print),
      ("error", "Create an error value. Usage: error \"message\"", builtin_error),

      ("load", "Import a LISP file and evaluate it. Usage: load \"filename.lispy\"", builtin_load),

      ("doc", "Add description to a symbol. Usage: doc {symbol} \"help text\"", builtin_doc),
      ("help", "Print information about a function or any other defined value. Usage: help {symbol}. Use help {env} to print out the current environment.", builtin_help),
    ]

    for (name, descr, builtin) in table {
      addBuiltinFunction(name, descr, builtin)
    }
  }
}

let globalEnv = Environment()
globalEnv.addBuiltinFunctions()

if case .Error(let message) = importFile(globalEnv, "stdlib.lispy") {
  print("Error loading standard library. \(message)")
}

// MARK: - Main loop

/*
  If Lispy is started without arguments, start the REPL. Otherwise, we load and
  execute each of the specified source files.
*/

var args = Process.arguments
if args.count > 1 {
  args.removeFirst()
  for arg in args {
    if case .Error(let message) = importFile(globalEnv, arg) {
      print(message)
    }
  }
} else {
  repl(globalEnv)
}
