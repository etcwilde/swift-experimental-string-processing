//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2021-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

import _RegexParser
@_spi(RegexBuilder) import _StringProcessing

extension Regex {
  public init<Content: RegexComponent>(
    @RegexComponentBuilder _ content: () -> Content
  ) where Content.Output == Output {
    self = content().regex
  }
}

// A convenience protocol for builtin regex components that are initialized with
// a `DSLTree` node.
internal protocol _BuiltinRegexComponent: RegexComponent {
  init(_ regex: Regex<Output>)
}

extension _BuiltinRegexComponent {
  init(node: DSLTree.Node) {
    self.init(Regex(node: node))
  }
}

// MARK: - Combinators

// MARK: Concatenation

// Note: Concatenation overloads are currently gyb'd.

// TODO: Variadic generics
// struct Concatenation<W0, C0..., R0: RegexComponent, W1, C1..., R1: RegexComponent>
// where R0.Match == (W0, C0...), R1.Match == (W1, C1...)
// {
//   typealias Match = (Substring, C0..., C1...)
//   let regex: Regex<Output>
//   init(_ first: R0, _ second: R1) {
//     regex = .init(concat(r0, r1))
//   }
// }

// MARK: Quantification

// Note: Quantifiers are currently gyb'd.

/// Specifies how much to attempt to match when using a quantifier.
public struct QuantificationBehavior {
  internal enum Kind {
    case eagerly
    case reluctantly
    case possessively
  }

  var kind: Kind

  internal var astKind: AST.Quantification.Kind {
    switch kind {
    case .eagerly: return .eager
    case .reluctantly: return .reluctant
    case .possessively: return .possessive
    }
  }
}

extension DSLTree.Node {
  /// Generates a DSLTree node for a repeated range of the given DSLTree node.
  /// Individual public API functions are in the generated Variadics.swift file.
  static func repeating(
    _ range: Range<Int>,
    _ behavior: QuantificationBehavior,
    _ node: DSLTree.Node
  ) -> DSLTree.Node {
    // TODO: Throw these as errors
    assert(range.lowerBound >= 0, "Cannot specify a negative lower bound")
    assert(!range.isEmpty, "Cannot specify an empty range")

    switch (range.lowerBound, range.upperBound) {
    case (0, Int.max): // 0...
      return .quantification(.zeroOrMore, behavior.astKind, node)
    case (1, Int.max): // 1...
      return .quantification(.oneOrMore, behavior.astKind, node)
    case _ where range.count == 1: // ..<1 or ...0 or any range with count == 1
      // Note: `behavior` is ignored in this case
      return .quantification(.exactly(.init(faking: range.lowerBound)), .eager, node)
    case (0, _): // 0..<n or 0...n or ..<n or ...n
      return .quantification(.upToN(.init(faking: range.upperBound)), behavior.astKind, node)
    case (_, Int.max): // n...
      return .quantification(.nOrMore(.init(faking: range.lowerBound)), behavior.astKind, node)
    default: // any other range
      return .quantification(.range(.init(faking: range.lowerBound), .init(faking: range.upperBound)), behavior.astKind, node)
    }
  }
}

extension QuantificationBehavior {
  /// Match as much of the input string as possible, backtracking when
  /// necessary.
  public static var eagerly: QuantificationBehavior {
    .init(kind: .eagerly)
  }

  /// Match as little of the input string as possible, expanding the matched
  /// region as necessary to complete a match.
  public static var reluctantly: QuantificationBehavior {
    .init(kind: .reluctantly)
  }

  /// Match as much of the input string as possible, performing no backtracking.
  public static var possessively: QuantificationBehavior {
    .init(kind: .possessively)
  }
}

public struct OneOrMore<Output>: _BuiltinRegexComponent {
  public var regex: Regex<Output>

  internal init(_ regex: Regex<Output>) {
    self.regex = regex
  }

  // Note: Public initializers and operators are currently gyb'd. See
  // Variadics.swift.
}

public struct ZeroOrMore<Output>: _BuiltinRegexComponent {
  public var regex: Regex<Output>

  internal init(_ regex: Regex<Output>) {
    self.regex = regex
  }

  // Note: Public initializers and operators are currently gyb'd. See
  // Variadics.swift.
}

public struct Optionally<Output>: _BuiltinRegexComponent {
  public var regex: Regex<Output>

  internal init(_ regex: Regex<Output>) {
    self.regex = regex
  }

  // Note: Public initializers and operators are currently gyb'd. See
  // Variadics.swift.
}

public struct Repeat<Output>: _BuiltinRegexComponent {
  public var regex: Regex<Output>

  internal init(_ regex: Regex<Output>) {
    self.regex = regex
  }

  // Note: Public initializers and operators are currently gyb'd. See
  // Variadics.swift.
}

// MARK: Alternation

// TODO: Variadic generics
// @resultBuilder
// struct AlternationBuilder {
//   @_disfavoredOverload
//   func buildBlock<R: RegexComponent>(_ regex: R) -> R
//   func buildBlock<
//     R: RegexComponent, W0, C0...
//   >(
//     _ regex: R
//   ) -> R where R.Match == (W, C...)
// }

@resultBuilder
public struct AlternationBuilder {
  @_disfavoredOverload
  public static func buildPartialBlock<R: RegexComponent>(
    first component: R
  ) -> ChoiceOf<R.Output> {
    .init(component.regex)
  }

  public static func buildExpression<R: RegexComponent>(_ regex: R) -> R {
    regex
  }

  public static func buildEither<R: RegexComponent>(first component: R) -> R {
    component
  }

  public static func buildEither<R: RegexComponent>(second component: R) -> R {
    component
  }
}

public struct ChoiceOf<Output>: _BuiltinRegexComponent {
  public var regex: Regex<Output>

  internal init(_ regex: Regex<Output>) {
    self.regex = regex
  }

  public init(@AlternationBuilder _ builder: () -> Self) {
    self = builder()
  }
}

// MARK: - Capture

public struct Capture<Output>: _BuiltinRegexComponent {
  public var regex: Regex<Output>

  internal init(_ regex: Regex<Output>) {
    self.regex = regex
  }

  // Note: Public initializers are currently gyb'd. See Variadics.swift.
}

public struct TryCapture<Output>: _BuiltinRegexComponent {
  public var regex: Regex<Output>

  internal init(_ regex: Regex<Output>) {
    self.regex = regex
  }

  // Note: Public initializers are currently gyb'd. See Variadics.swift.
}

// MARK: - Backreference

public struct Reference<Capture>: RegexComponent {
  let id = ReferenceID()

  public init(_ captureType: Capture.Type = Capture.self) {}

  public var regex: Regex<Capture> {
    .init(node: .atom(.symbolicReference(id)))
  }
}

extension Regex.Match {
  public subscript<Capture>(_ reference: Reference<Capture>) -> Capture {
    self[reference.id]
  }
}
