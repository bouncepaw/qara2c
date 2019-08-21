# c.md

This document lists Qaraidel features for the C programming language.

## Supported C features

- Function blocks with `fn`.
- Struct declarations with `struct`.
- Enumeration declarations with `enum`.
- Union declarations with `union`.
- Multiple `#define` macros used as constants with `defconst`.

## struct point

- `int x`
  You can include docs here.
- `int y`

```c
A /* This code will be placed before closing semicolon,
     it can be used for declaring variables. */
```

## enum color

- `RED = 0`
- `GREEN`
- `BLUE`

```c
C /* Same here */
```

## union rgba

- `uint8 channels[4]`
- `uint32 color`

```c
W /* And here */
```

## defconst

- `STDIN 0`
- `STDOUT 1`

## fn main

> `int`
Types and things like that go to blockquote.

- `int argc`
- `char** argv`
  Parameters go to bulleted lists.

```c
/* This is body of the fuction */
return 0;
```
