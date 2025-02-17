# String processing algorithms

## Introduction

The Swift standard library's string processing algorithms are underpowered compared to other popular programming and scripting languages. Some of these omissions can be found in `NSString`, but these fundamental algorithms should have a place in the standard library.

We propose:

1. New regex-powered algorithms over strings, bringing the standard library up to parity with scripting languages
2. Generic `Collection` equivalents of these algorithms in terms of subsequences
3. `protocol CustomMatchingRegexComponent`, which allows 3rd party libraries to provide their industrial-strength parsers as intermixable components of regexes

This proposal is part of a larger [regex-powered string processing initiative](https://forums.swift.org/t/declarative-string-processing-overview/52459). Throughout the document, we will reference the still-in-progress [`RegexProtocol`, `Regex`](https://github.com/apple/swift-experimental-string-processing/blob/main/Documentation/Evolution/StronglyTypedCaptures.md), and result builder DSL, but these are in flux and not formally part of this proposal. Further discussion of regex specifics is out of scope of this proposal and better discussed in another thread (see [Pitch and Proposal Status](https://github.com/apple/swift-experimental-string-processing/issues/107) for links to relevant threads).

## Motivation

A number of common string processing APIs are missing from the Swift standard library. While most of the desired functionalities can be accomplished through a series of API calls, every gap adds a burden to developers doing frequent or complex string processing. For example, here's one approach to find the number of occurrences a substring ("banana") within a string:

```swift
let str = "A banana a day keeps the doctor away. I love bananas; banana are my favorite fruit."

var idx = str.startIndex
var ranges = [Range<String.Index>]()
while let r = str.range(of: "banana", options: [], range: idx..<str.endIndex) {
    if idx != str.endIndex {
        idx = str.index(after: r.lowerBound)
    }
    ranges.append(r)
}

print(ranges.count)
```

While in Python this is as simple as 

```python
str = "A banana a day keeps the doctor away. I love bananas; banana are my favorite fruit."
print(str.count("banana"))
```

We propose adding string processing algorithms so common tasks as such can be achieved as straightforwardly.

<details>
<summary> Comparison of how Swift's APIs stack up with Python's. </summary>

Note: Only a subset of Python's string processing API are included in this table for the following reasons:

- Functions to query if all characters in the string are of a specified category, such as `isalnum()` and `isalpha()`, are omitted. These are achievable in Swift by passing in the corresponding character set to `allSatisfy(_:)`, so they're omitted in this table for simplicity. 
- String formatting functions such as `center(length, character)` and `ljust(width, fillchar)` are also excluded here as this proposal focuses on matching and searching functionalities.

##### Search and replace

|Python |Swift  |
|---    |---    |
| `count(sub, start, end)` |  |
| `find(sub, start, end)`, `index(sub, start, end)` | `firstIndex(where:)` | 
| `rfind(sub, start, end)`, `rindex(sub, start, end)` | `lastIndex(where:)` | 
| `expandtabs(tabsize)`, `replace(old, new, count)` | `Foundation.replacingOccurrences(of:with:)` |
| `maketrans(x, y, z)` + `translate(table)` |

##### Prefix and suffix matching

|Python |Swift  |
|---    |---    |
| `startswith(prefix, start, end)` | `starts(with:)` or `hasPrefix(:)`| 
| `endswith(suffix, start, end)` | `hasSuffix(:)` | 
| `removeprefix(prefix)` | Test if string has prefix with `hasPrefix(:)`, then drop the prefix with `dropFirst(:)`|
| `removesuffix(suffix)` | Test if string has suffix with `hasSuffix(:)`, then drop the suffix with `dropLast(:)` |

##### Strip / trim

|Python |Swift  |
|---    |---    |
| `strip([chars])`| `Foundation.trimmingCharacters(in:)` |
| `lstrip([chars])` | `drop(while:)` |
| `rstrip([chars])` | Test character equality, then `dropLast()` iteratively |

##### Split

|Python |Swift  |
|---    |---    |
| `partition(sep)` | `Foundation.components(separatedBy:)` |
| `rpartition(sep)` |  |
| `split(sep, maxsplit)` | `split(separator:maxSplits:...)` |
| `splitlines(keepends)` | `split(separator:maxSplits:...)` | 
| `rsplit(sep, maxsplit)` |  |

</details>



### Complex string processing

Even with the API additions, more complex string processing quickly becomes unwieldy. Up-coming support for authoring regexes in Swift help alleviate this somewhat, but string processing in the modern world involves dealing with localization, standards-conforming validation, and other concerns for which a dedicated parser is required.

Consider parsing the date field `"Date: Wed, 16 Feb 2022 23:53:19 GMT"` in an HTTP header as a `Date` type. The naive approach is to search for a substring that looks like a date string (`16 Feb 2022`), and attempt to post-process it as a `Date` with a date parser:

```swift
let regex = Regex {
    capture {
        oneOrMore(.digit)
        " "
        oneOrMore(.word)
        " "
        oneOrMore(.digit)
    }
}

let dateParser = Date.ParseStrategy(format: "\(day: .twoDigits) \(month: .abbreviated) \(year: .padded(4))"
if let dateMatch = header.firstMatch(of: regex)?.0 {
    let date = try? Date(dateMatch, strategy: dateParser)
}
```

This requires writing a simplistic pre-parser before invoking the real parser. The pre-parser will suffer from being out-of-sync and less featureful than what the real parser can do.

Or consider parsing a bank statement to record all the monetary values in the last column:

```swift
let statement = """
CREDIT    04/06/2020    Paypal transfer    $4.99
CREDIT    04/03/2020    Payroll            $69.73
DEBIT     04/02/2020    ACH transfer       ($38.25)
DEBIT     03/24/2020    IRX tax payment    ($52,249.98)
"""
```

Parsing a currency string such as `$3,020.85` with regex is also tricky, as it can contain localized and currency symbols in addition to accounting conventions. This is why Foundation provides industrial-strength parsers for localized strings.


## Proposed solution 

### Complex string processing

We propose a `CustomMatchingRegexComponent` protocol which allows types from outside the standard library participate in regex builders and `RegexComponent` algorithms. This allows types, such as `Date.ParseStrategy` and `FloatingPointFormatStyle.Currency`, to be used directly within a regex:
                           
```swift
let dateRegex = Regex {
    capture(dateParser)
}

let date: Date = header.firstMatch(of: dateRegex).map(\.result.1) 

let currencyRegex = Regex {
    capture(.localizedCurrency(code: "USD").sign(strategy: .accounting))
}

let amount: [Decimal] = statement.matches(of: currencyRegex).map(\.result.1)
```

### String algorithm additions

We also propose the following regex-powered algorithms as well as their generic `Collection` equivalents. See the Detailed design section for a complete list of variation and overloads .

|Function | Description |
|---    |---    |
|`contains(_:) -> Bool` | Returns whether the collection contains the given sequence or `RegexComponent` |
|`starts(with:) -> Bool` | Returns whether the collection contains the same prefix as the specified `RegexComponent` |
|`trimPrefix(_:)`| Removes the prefix if it matches the given `RegexComponent` or collection |
|`firstRange(of:) -> Range?` | Finds the range of the first occurrence of a given sequence or `RegexComponent`|
|`ranges(of:) -> some Collection<Range>` | Finds the ranges of the all occurrences of a given sequence or `RegexComponent` within the collection |
|`replace(:with:subrange:maxReplacements)`| Replaces all occurrences of the sequence matching the given `RegexComponent` or sequence with a given collection |
|`split(by:)`| Returns the longest possible subsequences of the collection around elements equal to the given separator |
|`firstMatch(of:)`| Returns the first match of the specified `RegexComponent` within the collection |
|`matches(of:)`| Returns a collection containing all matches of the specified `RegexComponent` |



## Detailed design 

### `CustomMatchingRegexComponent`

`CustomMatchingRegexComponent` inherits from `RegexComponent` and satisfies its sole requirement; Conformers can be used with all of the string algorithms generic over `RegexComponent`.

```swift
/// A protocol for custom match functionality.
public protocol CustomMatchingRegexComponent : RegexComponent {
    /// Match the input string within the specified bounds, beginning at the given index, and return
    /// the end position (upper bound) of the match and the matched instance.
    /// - Parameters:
    ///   - input: The string in which the match is performed.
    ///   - index: An index of `input` at which to begin matching.
    ///   - bounds: The bounds in `input` in which the match is performed.
    /// - Returns: The upper bound where the match terminates and a matched instance, or `nil` if
    ///   there isn't a match.
    func match(
        _ input: String,
        startingAt index: String.Index,
        in bounds: Range<String.Index>
    ) -> (upperBound: String.Index, match: Match)?
}
```

<details>
<summary>Example for protocol conformance</summary>

We use Foundation `FloatingPointFormatStyle<Decimal>.Currency` as an example for protocol conformance. It would implement the `match` function with `Match` being a `Decimal`. It could also add a static function `.localizedCurrency(code:)` as a member of `RegexComponent`, so it can be referred as `.localizedCurrency(code:)` in the `Regex` result builder:

```swift
extension FloatingPointFormatStyle<Decimal>.Currency : CustomMatchingRegexComponent { 
    public func match(
        _ input: String,
        startingAt index: String.Index,
        in bounds: Range<String.Index>
    ) -> (upperBound: String.Index, match: Decimal)?
}

extension RegexComponent where Self == FloatingPointFormatStyle<Decimal>.Currency {
    public static func localizedCurrency(code: Locale.Currency) -> Self
}
```

Matching and extracting a localized currency amount, such as `"$3,020.85"`, can be done directly within a regex:

```swift
let regex = Regex {
    capture(.localizedCurreny(code: "USD"))
}
```
 
</details>


### String algorithm additions

#### Contains

```swift
extension Collection where Element: Equatable {
    /// Returns a Boolean value indicating whether the collection contains the
    /// given sequence.
    /// - Parameter other: A sequence to search for within this collection.
    /// - Returns: `true` if the collection contains the specified sequence,
    /// otherwise `false`.
    public func contains<S: Sequence>(_ other: S) -> Bool
        where S.Element == Element
}

extension BidirectionalCollection where SubSequence == Substring {
    /// Returns a Boolean value indicating whether the collection contains the
    /// given regex.
    /// - Parameter regex: A regex to search for within this collection.
    /// - Returns: `true` if the regex was found in the collection, otherwise
    /// `false`.
    public func contains<R: RegexComponent>(_ regex: R) -> Bool
}
```

#### Starts with

```swift
extension BidirectionalCollection where SubSequence == Substring {
    /// Returns a Boolean value indicating whether the initial elements of the
    /// sequence are the same as the elements in the specified regex.
    /// - Parameter regex: A regex to compare to this sequence.
    /// - Returns: `true` if the initial elements of the sequence matches the
    /// beginning of `regex`; otherwise, `false`.
    public func starts<R: RegexComponent>(with regex: R) -> Bool
}
```

#### Trim prefix

```swift
extension Collection {
    /// Returns a new collection of the same type by removing initial elements
    /// that satisfy the given predicate from the start.
    /// - Parameter predicate: A closure that takes an element of the sequence
    /// as its argument and returns a Boolean value indicating whether the
    /// element should be removed from the collection.
    /// - Returns: A collection containing the elements of the collection that are
    ///  not removed by `predicate`.
    public func trimmingPrefix(while predicate: (Element) throws -> Bool) rethrows -> SubSequence
}

extension Collection where SubSequence == Self {
    /// Removes the initial elements that satisfy the given predicate from the
    /// start of the sequence.
    /// - Parameter predicate: A closure that takes an element of the sequence
    /// as its argument and returns a Boolean value indicating whether the
    /// element should be removed from the collection.
    public mutating func trimPrefix(while predicate: (Element) throws -> Bool)
}

extension RangeReplaceableCollection {
    /// Removes the initial elements that satisfy the given predicate from the
    /// start of the sequence.
    /// - Parameter predicate: A closure that takes an element of the sequence
    /// as its argument and returns a Boolean value indicating whether the
    /// element should be removed from the collection.
    public mutating func trimPrefix(while predicate: (Element) throws -> Bool)
}

extension Collection where Element: Equatable {
    /// Returns a new collection of the same type by removing `prefix` from the
    /// start.
    /// - Parameter prefix: The collection to remove from this collection.
    /// - Returns: A collection containing the elements that does not match
    /// `prefix` from the start.
    public func trimmingPrefix<Prefix: Collection>(_ prefix: Prefix) -> SubSequence
        where Prefix.Element == Element
}

extension Collection where SubSequence == Self, Element: Equatable {
    /// Removes the initial elements that matches `prefix` from the start.
    /// - Parameter prefix: The collection to remove from this collection.
    public mutating func trimPrefix<Prefix: Collection>(_ prefix: Prefix)
        where Prefix.Element == Element
}

extension RangeReplaceableCollection where Element: Equatable {
    /// Removes the initial elements that matches `prefix` from the start.
    /// - Parameter prefix: The collection to remove from this collection.
    public mutating func trimPrefix<Prefix: Collection>(_ prefix: Prefix)
        where Prefix.Element == Element
}

extension BidirectionalCollection where SubSequence == Substring {
    /// Returns a new subsequence by removing the initial elements that matches
    /// the given regex.
    /// - Parameter regex: The regex to remove from this collection.
    /// - Returns: A new subsequence containing the elements of the collection
    /// that does not match `prefix` from the start.
    public func trimmingPrefix<R: RegexComponent>(_ regex: R) -> SubSequence
}

extension RangeReplaceableCollection
  where Self: BidirectionalCollection, SubSequence == Substring
{
    /// Removes the initial elements that matches the given regex.
    /// - Parameter regex: The regex to remove from this collection.
    public mutating func trimPrefix<R: RegexComponent>(_ regex: R)
}
```

#### First range

```swift
extension Collection where Element: Equatable {
    /// Finds and returns the range of the first occurrence of a given sequence
    /// within the collection.
    /// - Parameter sequence: The sequence to search for.
    /// - Returns: A range in the collection of the first occurrence of `sequence`.
    /// Returns nil if `sequence` is not found.
    public func firstRange<S: Sequence>(of sequence: S) -> Range<Index>? 
        where S.Element == Element
}

extension BidirectionalCollection where Element: Comparable {
    /// Finds and returns the range of the first occurrence of a given sequence
    /// within the collection.
    /// - Parameter other: The sequence to search for.
    /// - Returns: A range in the collection of the first occurrence of `sequence`.
    /// Returns `nil` if `sequence` is not found.
    public func firstRange<S: Sequence>(of other: S) -> Range<Index>?
        where S.Element == Element
}

extension BidirectionalCollection where SubSequence == Substring {
    /// Finds and returns the range of the first occurrence of a given regex
    /// within the collection.
    /// - Parameter regex: The regex to search for.
    /// - Returns: A range in the collection of the first occurrence of `regex`.
    /// Returns `nil` if `regex` is not found.
    public func firstRange<R: RegexComponent>(of regex: R) -> Range<Index>?
}
```

#### Ranges

```swift
extension Collection where Element: Equatable {
    /// Finds and returns the ranges of the all occurrences of a given sequence
    /// within the collection.
    /// - Parameter other: The sequence to search for.
    /// - Returns: A collection of ranges of all occurrences of `other`. Returns
    ///  an empty collection if `other` is not found.
    public func ranges<S: Sequence>(of other: S) -> some Collection<Range<Index>>
        where S.Element == Element
}

extension BidirectionalCollection where SubSequence == Substring {
    /// Finds and returns the ranges of the all occurrences of a given sequence
    /// within the collection.
    /// - Parameter regex: The regex to search for.
    /// - Returns: A collection or ranges in the receiver of all occurrences of
    /// `regex`. Returns an empty collection if `regex` is not found.
    public func ranges<R: RegexComponent>(of regex: R) -> some Collection<Range<Index>>
}
```

#### First match

```swift
extension BidirectionalCollection where SubSequence == Substring {
    /// Returns the first match of the specified regex within the collection.
    /// - Parameter regex: The regex to search for.
    /// - Returns: The first match of `regex` in the collection, or `nil` if
    /// there isn't a match.
    public func firstMatch<R: RegexComponent>(of regex: R) -> RegexMatch<R.Match>?
}
```

#### Matches

```swift
extension BidirectionalCollection where SubSequence == Substring {
    /// Returns a collection containing all matches of the specified regex.
    /// - Parameter regex: The regex to search for.
    /// - Returns: A collection of matches of `regex`.
    public func matches<R: RegexComponent>(of regex: R) -> some Collection<RegexMatch<R.Match>>
}
```

#### Replace

```swift
extension RangeReplaceableCollection where Element: Equatable {
    /// Returns a new collection in which all occurrences of a target sequence
    /// are replaced by another collection.
    /// - Parameters:
    ///   - other: The sequence to replace.
    ///   - replacement: The new elements to add to the collection.
    ///   - subrange: The range in the collection in which to search for `other`.
    ///   - maxReplacements: A number specifying how many occurrences of `other`
    ///   to replace. Default is `Int.max`.
    /// - Returns: A new collection in which all occurrences of `other` in
    /// `subrange` of the collection are replaced by `replacement`.    
    public func replacing<S: Sequence, Replacement: Collection>(
        _ other: S,
        with replacement: Replacement,
        subrange: Range<Index>,
        maxReplacements: Int = .max
    ) -> Self where S.Element == Element, Replacement.Element == Element
  
    /// Returns a new collection in which all occurrences of a target sequence
    /// are replaced by another collection.
    /// - Parameters:
    ///   - other: The sequence to replace.
    ///   - replacement: The new elements to add to the collection.
    ///   - maxReplacements: A number specifying how many occurrences of `other`
    ///   to replace. Default is `Int.max`.
    /// - Returns: A new collection in which all occurrences of `other` in
    /// `subrange` of the collection are replaced by `replacement`.
    public func replacing<S: Sequence, Replacement: Collection>(
        _ other: S,
        with replacement: Replacement,
        maxReplacements: Int = .max
    ) -> Self where S.Element == Element, Replacement.Element == Element
  
    /// Replaces all occurrences of a target sequence with a given collection
    /// - Parameters:
    ///   - other: The sequence to replace.
    ///   - replacement: The new elements to add to the collection.
    ///   - maxReplacements: A number specifying how many occurrences of `other`
    ///   to replace. Default is `Int.max`.
    public mutating func replace<S: Sequence, Replacement: Collection>(
        _ other: S,
        with replacement: Replacement,
        maxReplacements: Int = .max
    ) where S.Element == Element, Replacement.Element == Element
}

extension RangeReplaceableCollection where SubSequence == Substring {
    /// Returns a new collection in which all occurrences of a sequence matching
    /// the given regex are replaced by another collection.
    /// - Parameters:
    ///   - regex: A regex describing the sequence to replace.
    ///   - replacement: The new elements to add to the collection.
    ///   - subrange: The range in the collection in which to search for `regex`.
    ///   - maxReplacements: A number specifying how many occurrences of the
    ///   sequence matching `regex` to replace. Default is `Int.max`.
    /// - Returns: A new collection in which all occurrences of subsequence
    /// matching `regex` in `subrange` are replaced by `replacement`.
    public func replacing<R: RegexComponent, Replacement: Collection>(
        _ regex: R,
        with replacement: Replacement,
        subrange: Range<Index>,
        maxReplacements: Int = .max
    ) -> Self where Replacement.Element == Element
  
    /// Returns a new collection in which all occurrences of a sequence matching
    /// the given regex are replaced by another collection.
    /// - Parameters:
    ///   - regex: A regex describing the sequence to replace.
    ///   - replacement: The new elements to add to the collection.
    ///   - maxReplacements: A number specifying how many occurrences of the
    ///   sequence matching `regex` to replace. Default is `Int.max`.
    /// - Returns: A new collection in which all occurrences of subsequence
    /// matching `regex` are replaced by `replacement`.
    public func replacing<R: RegexComponent, Replacement: Collection>(
        _ regex: R,
        with replacement: Replacement,
        maxReplacements: Int = .max
    ) -> Self where Replacement.Element == Element
  
    /// Replaces all occurrences of the sequence matching the given regex with
    /// a given collection.
    /// - Parameters:
    ///   - regex: A regex describing the sequence to replace.
    ///   - replacement: The new elements to add to the collection.
    ///   - maxReplacements: A number specifying how many occurrences of the
    ///   sequence matching `regex` to replace. Default is `Int.max`.
    public mutating func replace<R: RegexComponent, Replacement: Collection>(
        _ regex: R,
        with replacement: Replacement,
        maxReplacements: Int = .max
    ) where Replacement.Element == Element
  
    /// Returns a new collection in which all occurrences of a sequence matching
    /// the given regex are replaced by another regex match.
    /// - Parameters:
    ///   - regex: A regex describing the sequence to replace.
    ///   - replacement: A closure that receives the full match information,
    ///   including captures, and returns a replacement collection.
    ///   - subrange: The range in the collection in which to search for `regex`.
    ///   - maxReplacements: A number specifying how many occurrences of the
    ///   sequence matching `regex` to replace. Default is `Int.max`.
    /// - Returns: A new collection in which all occurrences of subsequence
    /// matching `regex` are replaced by `replacement`.
    public func replacing<R: RegexComponent, Replacement: Collection>(
        _ regex: R,
        with replacement: (RegexMatch<R.Match>) throws -> Replacement,
        subrange: Range<Index>,
        maxReplacements: Int = .max
    ) rethrows -> Self where Replacement.Element == Element
  
    /// Returns a new collection in which all occurrences of a sequence matching
    /// the given regex are replaced by another collection.
    /// - Parameters:
    ///   - regex: A regex describing the sequence to replace.
    ///   - replacement: A closure that receives the full match information,
    ///   including captures, and returns a replacement collection.
    ///   - maxReplacements: A number specifying how many occurrences of the
    ///   sequence matching `regex` to replace. Default is `Int.max`.
    /// - Returns: A new collection in which all occurrences of subsequence
    /// matching `regex` are replaced by `replacement`.
    public func replacing<R: RegexComponent, Replacement: Collection>(
        _ regex: R,
        with replacement: (RegexMatch<R.Match>) throws -> Replacement,
        maxReplacements: Int = .max
    ) rethrows -> Self where Replacement.Element == Element
  
    /// Replaces all occurrences of the sequence matching the given regex with
    /// a given collection.
    /// - Parameters:
    ///   - regex: A regex describing the sequence to replace.
    ///   - replacement: A closure that receives the full match information,
    ///   including captures, and returns a replacement collection.
    ///   - maxReplacements: A number specifying how many occurrences of the
    ///   sequence matching `regex` to replace. Default is `Int.max`.
    public mutating func replace<R: RegexComponent, Replacement: Collection>(
        _ regex: R,
        with replacement: (RegexMatch<R.Match>) throws -> Replacement,
        maxReplacements: Int = .max
    ) rethrows where Replacement.Element == Element
}
```

#### Split

```swift
extension Collection where Element: Equatable {
    /// Returns the longest possible subsequences of the collection, in order,
    /// around elements equal to the given separator.
    /// - Parameter separator: The element to be split upon.
    /// - Returns: A collection of subsequences, split from this collection's
    /// elements.
    public func split<S: Sequence>(by separator: S) -> some Collection<SubSequence>
        where S.Element == Element
}

extension BidirectionalCollection where SubSequence == Substring {
    /// Returns the longest possible subsequences of the collection, in order,
    /// around elements equal to the given separator.
    /// - Parameter separator: A regex describing elements to be split upon.
    /// - Returns: A collection of substrings, split from this collection's
    /// elements.
    public func split<R: RegexComponent>(by separator: R) -> some Collection<Substring>
}
```





## Alternatives considered

### Extend `Sequence` instead of `Collection`

Most of the proposed algorithms are necessarily on `Collection` due to the use of indices or mutation.  `Sequence` does not support multi-pass iteration, so even `trimPrefix` would problematic on `Sequence` because it needs to look 1 `Element` ahead to know when to stop trimming.

## Future directions

### Backward algorithms

It would be useful to have algorithms that operate from the back of a collection, including ability to find the last non-overlapping range of a pattern in a string, and/or that to find the first range of a pattern when searching from the back, and trimming a string from both sides. They are deferred from this proposal as the API that could clarify the nuances of backward algorithms are still being explored. 

<details>
<summary> Nuances of backward algorithms </summary>

There is a subtle difference between finding the last non-overlapping range of a pattern in a string, and finding the first range of this pattern when searching from the back. 

The currently proposed algorithm that finds a pattern from the front, e.g. `"aaaaa".ranges(of: "aa")`, produces two non-overlapping ranges, splitting the string in the chunks `aa|aa|a`. It would not be completely unreasonable to expect to introduce a counterpart, such as `"aaaaa".lastRange(of: "aa")`, to return the range that contains the third and fourth characters of the string. This would be a shorthand for `"aaaaa".ranges(of: "aa").last`. Yet, it would also be reasonable to expect the function to return the first range of `"aa"` when searching from the back of the string, i.e. the range that contains the fourth and fifth characters. 

Trimming a string from both sides shares a similar story. For example, `"ababa".trimming("aba")` can return either `"ba"` or `"ab"`, depending on whether the prefix or the suffix was trimmed first. 
</details>

 
### Future API

Some Python functions are not currently included in this proposal, such as trimming the suffix from a string/collection. This pitch aims to establish a pattern for using `RegexComponent` with string processing algorithms, so that further enhancement can to be introduced to the standard library easily in the future, and eventually close the gap between Swift and other popular scripting languages. 
