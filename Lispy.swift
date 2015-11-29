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
      return .Error(message: "Unbound symbol '\(name)'")
    }
  }

  func put(name name: String, value: Value) {
    dictionary[name] = value
  }

  func addBuiltinFunction(name: String, _ code: Builtin) {
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

// MARK: - Q-Expression functions

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

// MARK: - Functions for variables

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
    addBuiltinFunction("len", builtin_len)
    addBuiltinFunction("cons", builtin_cons)

    // Mathematical functions
    addBuiltinFunction("+", builtin_add)
    addBuiltinFunction("-", builtin_subtract)
    addBuiltinFunction("*", builtin_multiply)
    addBuiltinFunction("/", builtin_divide)

    // Variable functions
    addBuiltinFunction("def", builtin_def)
    addBuiltinFunction("printenv", builtin_printenv)
  }
}

let e = Environment()
e.addBuiltinFunctions()

// MARK: - REPL

func readInput() -> String {
  let keyboard = NSFileHandle.fileHandleWithStandardInput()
  let inputData = keyboard.availableData
  let string = NSString(data: inputData, encoding: NSUTF8StringEncoding)!
  return string.stringByTrimmingCharactersInSet(NSCharacterSet.newlineCharacterSet())
}

print("Lispy Version 0.11")
print("Press Ctrl+c to Exit")

while true {
  print("lispy> ", terminator: "")
  fflush(__stdoutp)

  let input = readInput()
  let v = parse(input)
  if case .Error(let message) = v {
    print("Error: \(message)")
  } else {
    print(v.eval(e))
  }
}
