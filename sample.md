# Sample

A scratch file that exercises every path the highlighter handles.

## Inline

Ordinary prose with **bold**, _italic_, __also bold__, *also italic*,
~~struck through~~, and `inline code`. A [link](https://example.com) and a
bare URL https://example.com and an autolink <https://example.com>.

### Third level

#### Fourth level

## Quotes

> Writing is thinking. To write well is to think clearly.
> That's why it's so hard.

## Lists

- First
- Second with **emphasis**
  - Nested
1. Ordered
2. Also ordered

- [ ] Unchecked task
- [x] Checked task, struck through

## Code

```swift
func measure(_ text: String) -> Int {
    text.split(whereSeparator: \.isWhitespace).count
}
```

## Table

| Column | Meaning |
|--------|---------|
| Measure | Characters per line |
| Leading | Space between lines |

---

Everything after the rule is ordinary text again.
