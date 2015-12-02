import Foundation

/*
  A conversion of www.buildyourownlisp.com into Swift.
*/

// MARK: - Values

typealias Builtin = (env: Environment, values: [Value]) -> Value

enum Value {
  case Error(message: String)
  case Number(value: Int)
  case Symbol(name: String)
  case SExpression(values: [Value])
  case QExpression(values: [Value])
  case BuiltinFunction(name: String, code: Builtin)

  // The formal parameters are an array of symbols. The body is a Q-Expression.
  // The environment is needed for partial function application, because it has
  // the values of the parameters that have been used already.
  indirect case Lambda(env: Environment, formals: [String], body: Value)
}

extension Value {
  static func empty() -> Value {
    return .SExpression(values: [])
  }
}

extension Value: Equatable {
}

func ==(lhs: Value, rhs: Value) -> Bool {
  switch (lhs, rhs) {
  case (.Error(let message1), .Error(let message2)):
    return message1 == message2
  case (.Number(let value1), .Number(let value2)):
    return value1 == value2
  case (.Symbol(let name1), .Symbol(let name2)):
    return name1 == name2
  case (.BuiltinFunction(let name1, _), .BuiltinFunction(let name2, _)):
    return name1 == name2
  case (.Lambda(_, let formals1, let body1), .Lambda(_, let formals2, let body2)):
    return formals1 == formals2 && body1 == body2
  case (.SExpression(let values1), .SExpression(let values2)):
    return values1 == values2
  case (.QExpression(let values1), .QExpression(let values2)):
    return values1 == values2
  default:
    return false
  }
}

extension Value: CustomStringConvertible {
  var description: String {
    switch self {
    case .Error(let message):
      return "Error: \(message)"
    case Number(let value):
      return "\(value)"
    case Symbol(let name):
      return name
    case BuiltinFunction(let name, _):
      return "<\(name)>"
    case Lambda(let env, let formals, let body):
      var s = "(\\ {\(listToString(formals))} \(body))"
      if !env.dictionary.isEmpty {
        s += " ["
        for (k, v) in env.dictionary {
          s += " \(k)=\(v)"
        }
        s += " ]"
      }
      return s
    case SExpression(let values):
      return "(" + listToString(values) + ")"
    case QExpression(let values):
      return "{" + listToString(values) + "}"
    }
  }

  private func listToString(values: [Value]) -> String {
    return values.map({ $0.description }).joinWithSeparator(" ")
  }

  private func listToString(values: [String]) -> String {
    return values.joinWithSeparator(" ")
  }

  var typeName: String {
    switch self {
    case .Error: return "Error"
    case Number: return "Number"
    case Symbol: return "Symbol"
    case BuiltinFunction: return "Built-in Function"
    case Lambda: return "Lambda"
    case SExpression: return "S-Expression"
    case QExpression: return "Q-Expression"
    }
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

// MARK: - Environment

class Environment {
  private(set) var dictionary = [String: Value]()

  var parent: Environment?

  // Making a copy is necessary for partial function application
  // (because Environment is a reference type, not a value type).
  func copy() -> Environment {
    let e = Environment()
    e.dictionary = dictionary
    e.parent = parent
    return e
  }

  func get(name: String) -> Value {
    if let v = dictionary[name] {
      return v
    } else if let parent = parent {
      return parent.get(name)
    } else {
      return .Error(message: "Unbound symbol '\(name)'")
    }
  }

  func put(name name: String, value: Value) {
    dictionary[name] = value
  }

  func globalEnvironment() -> Environment {
    var env = self
    while case let parent? = env.parent {
      env = parent
    }
    return env
  }

  func addBuiltinFunction(name: String, _ code: Builtin) {
    put(name: name, value: .BuiltinFunction(name: name, code: code))
  }
}

extension Environment: CustomStringConvertible {
  var description: String {
    var s = ""
    if parent == nil {
      s += "---Environment (global)---\n"
    } else {
      s += "---Environment (local)---\n"
    }
    for name in dictionary.keys.sort(<) {
      let value = dictionary[name]!
      if case .BuiltinFunction = value {
        s += "\(name) \(value.typeName)\n"
      } else {
        s += "\(name) \(value.typeName) \(value)\n"
      }
    }
    return s + "--------------------------"
  }
}

// MARK: - Evaluating

// Takes one or more values and returns a new Q-Expression containing those values.
let builtin_list: Builtin = { _, values in
  return .QExpression(values: values)
}

extension Value {
  func eval(env: Environment) -> Value {
    //print("eval \(self)")

    switch self {
      // Return the value associated with the symbol in the environment.
    case .Symbol(let name):
      return env.get(name)

      // Evaluate the values inside the S-Expression recursively.
    case .SExpression(let values):
      return evalList(env, values)

      // All other value types are passed along literally without evaluating
    default:
      return self
    }
  }

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

    // Empty expression.
    if values.count == 0 { return Value.empty() }

    // Single expression; simply return the first (and only) child.
    if values.count == 1 { return values[0] }

    // Ensure first value is a function after evaluation, then call it on the
    // remaining values.
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

  private func evalLambda(parentEnv: Environment, _ localEnv: Environment, var _ formals: [String], var _ args: [Value], _ body: Value) -> Value {
    let given = args.count
    let expected = formals.count

    // While arguments still remain to be processed...
    while args.count > 0 {
      // Have we ran out of formal arguments to bind?
      if formals.count == 0 {
        return .Error(message: "Expected \(expected) arguments, got \(given)")
      }

      // Look at the next symbol from the formals.
      let sym = formals.removeFirst()

      // Special case to deal with '&' for variable-argument lists
      if sym == "&" {
        // Ensure '&' is followed by another symbol.
        if formals.count != 1 {
          return .Error(message: "Expected a single following '&'")
        }

        // The next formal should be bound to remaining arguments.
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

      // Delete '&' symbol.
      formals.removeFirst()

      // Associate the next (and final) symbol with an empty list.
      let sym = formals.removeFirst()
      localEnv.put(name: sym, value: .QExpression(values: []))
    }

    // If all formals have been bound, evaluate the function body.
    if formals.count == 0 {
      localEnv.parent = parentEnv
      return builtin_eval(env: localEnv, values: [body])
    } else {
      // Otherwise return partially evaluated function.
      return .Lambda(env: localEnv, formals: formals, body: body)
    }
  }
}

// MARK: - Q-Expression functions

// Takes a Q-Expression and evaluates it as if it were a S-Expression.
let builtin_eval: Builtin = { env, values in
  if values.count != 1 {
    return .Error(message: "Function 'eval' expected 1 argument, got \(values.count)")
  }
  guard case .QExpression(let qvalues) = values[0] else {
    return .Error(message: "Function 'eval' expected Q-Expression, got \(values[0])")
  }
  return Value.SExpression(values: qvalues).eval(env)
}

// Takes a Q-Expression and returns a new Q-Expression with only the first value.
let builtin_head: Builtin = { _, values in
  if values.count != 1 {
    return .Error(message: "Function 'head' expected 1 argument, got \(values.count)")
  }
  guard case .QExpression(let qvalues) = values[0] else {
    return .Error(message: "Function 'head' expected Q-Expression, got \(values[0])")
  }
  if qvalues.count == 0 {
    return .Error(message: "Function 'head' expected non-empty Q-Expression, got {}")
  }
  return .QExpression(values: [qvalues[0]])
}

// Takes a Q-Expression and returns a new Q-Expression with the first value removed.
let builtin_tail: Builtin = { env, values in
  if values.count != 1 {
    return .Error(message: "Function 'tail' expected 1 argument, got \(values.count)")
  }
  guard case .QExpression(var qvalues) = values[0] else {
    return .Error(message: "Function 'tail' expected Q-Expression, got \(values[0])")
  }
  if qvalues.count == 0 {
    return .Error(message: "Function 'tail' expected non-empty Q-Expression, got {}")
  }
  qvalues.removeFirst()
  return .QExpression(values: qvalues)
}

// Returns all of a Q-Expression except the final value.
let builtin_init: Builtin = { env, values in
  if values.count != 1 {
    return .Error(message: "Function 'init' expected 1 argument, got \(values.count)")
  }
  guard case .QExpression(var qvalues) = values[0] else {
    return .Error(message: "Function 'init' expected Q-Expression, got \(values[0])")
  }
  if qvalues.count == 0 {
    return .Error(message: "Function 'init' expected non-empty Q-Expression, got {}")
  }
  qvalues.removeLast()
  return .QExpression(values: qvalues)
}

// Takes one or more Q-Expressions and puts them all into a single new Q-Expression.
let builtin_join: Builtin = { env, values in
  var allValues = [Value]()
  for value in values {
    if case .QExpression(let qvalues) = value {
      allValues += qvalues
    } else {
      return .Error(message: "Function 'join' expected Q-Expression, got \(value)")
    }
  }
  return .QExpression(values: allValues)
}

// Takes a value and a Q-Expression and appends the value to the front of the list.
let builtin_cons: Builtin = { env, values in
  if values.count != 2 {
    return .Error(message: "Function 'cons' expected 2 arguments, got \(values.count)")
  }
  guard case .QExpression(let qvalues) = values[1] else {
    return .Error(message: "Function 'cons' expected Q-Expression, got \(values[1])")
  }
  return .QExpression(values: [values[0]] + qvalues)
}

// MARK: - Mathematical functions

typealias Operator = (Value, Value) -> Value

func curry(op: (Int, Int) -> Int)(_ lhs: Value, _ rhs: Value) -> Value {
  guard case .Number(let x) = lhs else {
    return .Error(message: "Expected number, got \(lhs)")
  }
  guard case .Number(let y) = rhs else {
    return .Error(message: "Expected number, got \(rhs)")
  }
  return .Number(value: op(x, y))
}

func performOnList(env: Environment, var _ values: [Value], _ op: Operator) -> Value {
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
    if case .Number(let x) = values[0] {  // perform unary negation
      return .Number(value: -x)
    } else {
      return .Error(message: "Expected number, got \(values[0])")
    }
  }
  return performOnList(env, values, curry(-))
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

// MARK: - Comparison functions

func curry(op: (Int, Int) -> Bool)(_ lhs: Value, _ rhs: Value) -> Value {
  guard case .Number(let x) = lhs else {
    return .Error(message: "Expected number, got \(lhs)")
  }
  guard case .Number(let y) = rhs else {
    return .Error(message: "Expected number, got \(rhs)")
  }
  return .Number(value: op(x, y) ? 1 : 0)
}

func comparison(env: Environment, var _ values: [Value], _ op: Operator) -> Value {
  if values.count != 2 {
    return .Error(message: "Comparison expected 2 arguments, got \(values.count)")
  }
  return op(values[0], values[1])
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
  if values.count != 2 {
    return .Error(message: "Function '==' expected 1 arguments, got \(values.count)")
  }
  return .Number(value: values[0] == values[1] ? 1 : 0)
}

let builtin_ne: Builtin = { env, values in
  if values.count != 2 {
    return .Error(message: "Function '!=' expected 2 arguments, got \(values.count)")
  }
  return .Number(value: values[0] != values[1] ? 1 : 0)
}

let builtin_if: Builtin = { env, values in
  if values.count != 3 {
    return .Error(message: "Function 'if' expected 3 arguments, got \(values.count)")
  }
  guard case .Number(let cond) = values[0] else {
    return .Error(message: "Function 'if' expected number, got \(values[0])")
  }
  guard case .QExpression(var qvalues1) = values[1] else {
    return .Error(message: "Function 'if' expected Q-Expression, got \(values[1])")
  }
  guard case .QExpression(var qvalues2) = values[2] else {
    return .Error(message: "Function 'if' expected Q-Expression, got \(values[2])")
  }

  // If condition is true, evaluate first expression, otherwise second.
  if cond != 0 {
    return Value.SExpression(values: qvalues1).eval(env)
  } else {
    return Value.SExpression(values: qvalues2).eval(env)
  }
}

// MARK: - Functions for variables and lambdas

// Associates a new value with a symbol. This adds it to the environment.
// Takes a Q-Expression and one or more values.
func bindVariable(env: Environment, _ values: [Value]) -> Value {
  guard case .QExpression(let qvalues) = values[0] else {
    return .Error(message: "Expected Q-Expression, got \(values[0])")
  }

  // For convenience, put the symbols from the Q-Expression into this array.
  var symbols = [String]()

  // Ensure all values from the Q-Expression are symbols.
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

// Prints out the contents of the environment.
let builtin_printenv: Builtin = { env, values in
  print(env)
  return Value.empty()
}

let builtin_lambda: Builtin = { env, values in
  if values.count != 2 {
    return .Error(message: "Function '\\' expected 2 arguments, got \(values.count)")
  }
  guard case .QExpression(var qvalues) = values[0] else {
    return .Error(message: "Function '\\' expected Q-Expression, got \(values[0])")
  }
  guard case .QExpression = values[1] else {
    return .Error(message: "Function '\\' expected Q-Expression, got \(values[1])")
  }

  var symbols = [String]()

  // Check that the first Q-Expression contains only symbols.
  for value in qvalues {
    if case .Symbol(let name) = value {
      symbols.append(name)
    } else {
      return .Error(message: "Expected symbol, got \(value)")
    }
  }

  return .Lambda(env: Environment(), formals: symbols, body: values[1])
}

// MARK: - Parser

/*
  This is a simplified version of the parser used in the original tutorial.
*/

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

func parse(s: String) -> Value {
  var i = s.startIndex
  return tokenizeList(s, &i, "")
}

// MARK: - Initialization

extension Environment {
  func addBuiltinFunctions() {
    // List functions
    addBuiltinFunction("eval", builtin_eval)
    addBuiltinFunction("list", builtin_list)
    addBuiltinFunction("head", builtin_head)
    addBuiltinFunction("tail", builtin_tail)
    addBuiltinFunction("init", builtin_init)
    addBuiltinFunction("join", builtin_join)
    addBuiltinFunction("cons", builtin_cons)

    // Mathematical functions
    addBuiltinFunction("+", builtin_add)
    addBuiltinFunction("-", builtin_subtract)
    addBuiltinFunction("*", builtin_multiply)
    addBuiltinFunction("/", builtin_divide)

    // Comparison functions
    addBuiltinFunction(">", builtin_gt)
    addBuiltinFunction("<", builtin_lt)
    addBuiltinFunction(">=", builtin_ge)
    addBuiltinFunction("<=", builtin_le)
    addBuiltinFunction("==", builtin_eq)
    addBuiltinFunction("!=", builtin_ne)
    addBuiltinFunction("if", builtin_if)

    // Variable and lambda functions
    addBuiltinFunction("def", builtin_def)
    addBuiltinFunction("=", builtin_put)
    addBuiltinFunction("\\", builtin_lambda)
    addBuiltinFunction("printenv", builtin_printenv)
  }

  func addUsefulFunctions() {
    let xs = [
      // Allows you to write: fun {add-together x y} {+ x y}
      "def {fun} (\\ {args body} {def (head args) (\\ (tail args) body)})",

      "fun {unpack f xs} {eval (join (list f) xs)}",
      "def {curry} unpack",

      "fun {pack f & xs} {f xs}",
      "def {uncurry} pack",

      // Reverses the elements from a list.
      "fun {reverse l} {" +
      "  if (== l {})" +
      "    {{}}" +
      "    {join (reverse (tail l)) (head l)}" +
      "}",

      // Determines the number of items in a list.
      "fun {len l} {" +
      "  if (== l {})" +
      "    {0}" +
      "    {+ 1 (len (tail l))}" +
      "}",
    ]

    for x in xs {
      let v = parse(x)
      if case .Error(let message) = v.eval(self) {
        print("Error: \(message)")
      }
    }
  }
}

let e = Environment()
e.addBuiltinFunctions()
e.addUsefulFunctions()

// MARK: - REPL

func readInput() -> String {
  let keyboard = NSFileHandle.fileHandleWithStandardInput()
  let inputData = keyboard.availableData
  let string = NSString(data: inputData, encoding: NSUTF8StringEncoding)!
  return string.stringByTrimmingCharactersInSet(NSCharacterSet.newlineCharacterSet())
}

print("Lispy Version 0.13")
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

  let v = parse(lines)
  if case .Error(let message) = v {
    print("Error: \(message)")
  } else {
    print(v.eval(e))
  }

  lines = ""
}
