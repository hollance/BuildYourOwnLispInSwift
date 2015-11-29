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
  case Function(name: String, code: Builtin)
  case SExpression(values: [Value])
  case QExpression(values: [Value])
}

extension Value {
  static func empty() -> Value {
    return .SExpression(values: [])
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
    case Function(let name, _):
      return "<\(name)>"
    case SExpression(let values):
      return "(" + listToString(values) + ")"
    case QExpression(let values):
      return "{" + listToString(values) + "}"
    }
  }

  private func listToString(values: [Value]) -> String {
    return values.map({ $0.description }).joinWithSeparator(" ")
  }

  var typeName: String {
    switch self {
    case .Error: return "Error"
    case Number: return "Number"
    case Symbol: return "Symbol"
    case Function: return "Function"
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

  func get(name: String) -> Value {
    if let v = dictionary[name] {
      return v
    } else {
      return .Error(message: String(format: "Unbound symbol '%@'", name))
    }
  }

  func put(name name: String, value: Value) {
    dictionary[name] = value
  }

  func addBuiltinFunction(name name: String, code: Builtin) {
    put(name: name, value: .Function(name: name, code: code))
  }
}

extension Environment: CustomStringConvertible {
  var description: String {
    var s = ""
    for name in dictionary.keys.sort(<) {
      let value = dictionary[name]!
      if case .Function = value {
        s += "\(name) \(value.typeName)\n"
      } else {
        s += "\(name) \(value.typeName) \(value)\n"
      }
    }
    return s
  }
}

// MARK: - Evaluating

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
    //print("BEFORE \(values)")

    // Evaluate children. If any of them are symbols, they will be converted into
    // the associated value from the environment, such as a function, a number, or
    // a Q-Expression.
    for var i = 0; i < values.count; ++i {
      values[i] = values[i].eval(env)
    }

    //print("AFTER \(values)")

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
    if case .Function(_, let code) = first {
      return code(env: env, values: values)
    }
    return .Error(message: "Expected function, got \(first)")
  }
}

// MARK: - Built-in functions

// Takes a Q-Expression and evaluates it as if it were a S-Expression.
let builtin_eval: Builtin = { env, values in
  if values.count != 1 {
    return .Error(message: "Function 'eval' expects 1 argument, got \(values.count)")
  }
  guard case .QExpression(let qvalues) = values[0] else {
    return .Error(message: "Function 'eval' expects Q-Expression, got \(values[0])")
  }
  return Value.SExpression(values: qvalues).eval(env)
}

// Takes one or more values and returns a new Q-Expression containing those values.
let builtin_list: Builtin = { _, values in
  return .QExpression(values: values)
}

// Takes a Q-Expression and returns a new Q-Expression with only the first value.
let builtin_head: Builtin = { _, values in
  if values.count != 1 {
    return .Error(message: "Function 'head' expects 1 argument, got \(values.count)")
  }
  guard case .QExpression(let qvalues) = values[0] else {
    return .Error(message: "Function 'head' expects Q-Expression, got \(values[0])")
  }
  if qvalues.count == 0 {
    return .Error(message: "Function 'head' expects non-empty Q-Expression, got {}")
  }
  return qvalues[0]
}

// Takes a Q-Expression and returns a new Q-Expression with the first value removed.
let builtin_tail: Builtin = { env, values in
  if values.count != 1 {
    return .Error(message: "Function 'tail' expects 1 argument, got \(values.count)")
  }
  guard case .QExpression(var qvalues) = values[0] else {
    return .Error(message: "Function 'tail' expects Q-Expression, got \(values[0])")
  }
  if qvalues.count == 0 {
    return .Error(message: "Function 'tail' expects non-empty Q-Expression, got {}")
  }
  qvalues.removeFirst()
  return .QExpression(values: qvalues)
}

// Returns all of a Q-Expression except the final value.
let builtin_init: Builtin = { env, values in
  if values.count != 1 {
    return .Error(message: "Function 'init' expects 1 argument, got \(values.count)")
  }
  guard case .QExpression(var qvalues) = values[0] else {
    return .Error(message: "Function 'init' expects Q-Expression, got \(values[0])")
  }
  if qvalues.count == 0 {
    return .Error(message: "Function 'init' expects non-empty Q-Expression, got {}")
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
      return .Error(message: "Function 'join' expects Q-Expression, got \(value)")
    }
  }
  return .QExpression(values: allValues)
}

// Returns the number of value in a Q-Expression.
let builtin_len: Builtin = { env, values in
  if values.count != 1 {
    return .Error(message: "Function 'len' expects 1 argument, got \(values.count)")
  }
  guard case .QExpression(let qvalues) = values[0] else {
    return .Error(message: "Function 'len' expects Q-Expression, got \(values[0])")
  }
  return .Number(value: qvalues.count)
}

// Takes a value and a Q-Expression and appends the value to the front of the list.
let builtin_cons: Builtin = { env, values in
  if values.count != 2 {
    return .Error(message: "Function 'cons' expects 2 arguments, got \(values.count)")
  }
  guard case .QExpression(let qvalues) = values[1] else {
    return .Error(message: "Function 'cons' expects Q-Expression, got \(values[1])")
  }
  return .QExpression(values: [values[0]] + qvalues)
}

func builtinOperator(env: Environment, _ values: [Value], _ op: String) -> Value {
  // For convenience, put all the numbers into this array.
  var numbers = [Int]()

  // Ensure all arguments are numbers.
  for v in values {
    if case .Number(let number) = v {
      numbers.append(number)
    } else {
      return .Error(message: "Expected number, got \(v)")
    }
  }

  // Get the first number.
  var x = numbers.removeFirst()

  // If no arguments and subtraction, then perform unary negation.
  if op == "-" && numbers.isEmpty {
    return .Number(value: -x)
  }

  while !numbers.isEmpty {
    let y = numbers.removeFirst()

    if op == "+" { x += y }
    if op == "-" { x -= y }
    if op == "*" { x *= y }
    if op == "/" {
      if y == 0 {
        return .Error(message: "Division by zero")
      }
      x /= y
    }
  }
  return .Number(value: x)
}

let builtin_add = { env, values in builtinOperator(env, values, "+") }
let builtin_subtract = { env, values in builtinOperator(env, values, "-") }
let builtin_multiply = { env, values in builtinOperator(env, values, "*") }
let builtin_divide = { env, values in builtinOperator(env, values, "/") }

// Associates a new value with a symbol. This adds it to the environment.
// Takes a Q-Expression and one or more values.
let builtin_def: Builtin = { env, values in
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

// Prints out the contents of the environment.
let builtin_printenv: Builtin = { env, values in
  print("---Environment---")
  print(env.description, terminator: "")
  print("-----------------")
  return Value.empty()
}

func addBuiltins(env: Environment) {
  // List functions
  env.addBuiltinFunction(name: "eval", code: builtin_eval)
  env.addBuiltinFunction(name: "list", code: builtin_list)
  env.addBuiltinFunction(name: "head", code: builtin_head)
  env.addBuiltinFunction(name: "tail", code: builtin_tail)
  env.addBuiltinFunction(name: "init", code: builtin_init)
  env.addBuiltinFunction(name: "join", code: builtin_join)
  env.addBuiltinFunction(name: "len", code: builtin_len)
  env.addBuiltinFunction(name: "cons", code: builtin_cons)

  // Mathematical functions
  env.addBuiltinFunction(name: "+", code: builtin_add)
  env.addBuiltinFunction(name: "-", code: builtin_subtract)
  env.addBuiltinFunction(name: "*", code: builtin_multiply)
  env.addBuiltinFunction(name: "/", code: builtin_divide)

  // Variable functions
  env.addBuiltinFunction(name: "def", code: builtin_def)
  env.addBuiltinFunction(name: "printenv", code: builtin_printenv)
}

// MARK: - Demo

let e = Environment()
addBuiltins(e)

//let v1 = Value.Error(message: "Foutje")
//let v3 = Value.Number(value: -456)
//let v4 = Value.Function(name: "lol", code: { _ in return Value.empty() })
//let v5 = Value.Symbol(name: "x")
//let v6 = Value.Symbol(name: "+")
//let v7 = Value.QExpression(values: [.Symbol(name: "yay")])
//let v2 = Value.SExpression(values: [v6, v3, v5])
//
//// fake a "def"
////e.put(name: "something", value: .Number(value: 2048))
//
//// ( def { x y } 123 456 )
//let d3 = Value.QExpression(values: [.Symbol(name: "x"), .Symbol(name: "y")])
//let d2 = Value.Symbol(name: "def")
//let d1 = Value.SExpression(values: [d2, d3, .Number(value: 123), .Number(value: 456)])
//
//let d5 = Value.SExpression(values: [v6, .Number(value: 123), .Number(value: 456)])
//let d0 = Value.SExpression(values: [d2, d3, d5, .Number(value: 789)])
//
//print("> \(d0)")
//print(eval(e, d0))
//print(eval(e, v5))
//print("> \(d1)")
//print(eval(e, d1))
//print(eval(e, v5))
//print("> \(v2)")
//print(eval(e, v2))
//print(eval(e, Value.SExpression(values: [.Symbol(name: "printenv"), .Number(value: 1)])))
//
//let q1 = Value.QExpression(values: [.Symbol(name: "x"), .Symbol(name: "y"), .Symbol(name: "z")])
//
//print(eval(e, q1))
//print(eval(e, Value.SExpression(values: [.Symbol(name: "head"), q1])))
//print(eval(e, Value.SExpression(values: [.Symbol(name: "head"), .QExpression(values: [])])))
//print(eval(e, Value.SExpression(values: [.Symbol(name: "head"), .QExpression(values: [.Number(value: 100)])])))
//
//print(eval(e, Value.SExpression(values: [.Symbol(name: "list"), .Symbol(name: "x"), .Number(value: 200), q1])))
//
//print(eval(e, Value.SExpression(values: [.Symbol(name: "tail"), q1])))
//print(eval(e, Value.SExpression(values: [.Symbol(name: "tail"), .QExpression(values: [])])))
//print(eval(e, Value.SExpression(values: [.Symbol(name: "tail"), .QExpression(values: [.Number(value: 100)])])))
//
//let q2 = Value.QExpression(values: [.Symbol(name: "list"), .Number(value: 1), .Number(value: 2)])
//print(eval(e, q2))
//print(eval(e, Value.SExpression(values: [.Symbol(name: "eval"), q2])))
//
//print(eval(e, Value.SExpression(values: [.Symbol(name: "join"), q2, q2])))
//print(eval(e, Value.SExpression(values: [.Symbol(name: "len"), q2])))
//print(eval(e, Value.SExpression(values: [.Symbol(name: "len"), .QExpression(values: [])])))
//print(eval(e, Value.SExpression(values: [.Symbol(name: "cons"), .Number(value: 3), q2])))
//print(eval(e, Value.SExpression(values: [.Symbol(name: "cons"), q2, q2])))
//print(eval(e, Value.SExpression(values: [.Symbol(name: "init"), q2])))

let v3: Value = -456
print(v3.eval(e))

let q1 = Value.QExpression(values: ["x", .Symbol(name: "y"), .Symbol(name: "z")])
print(q1.eval(e))

let s1 = Value.SExpression(values: ["head", ["X", "Y", "Z"]])
print(s1.eval(e))

let q2: Value = ["X", "Y", "Z"]
print(q2.eval(e))

