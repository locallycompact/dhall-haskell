{-# OPTIONS_GHC -fno-warn-unused-imports #-}

{-| Dhall is a programming language specialized for configuration files.  This
    module contains a tutorial explaning how to author configuration files using
    this language
-}
module Dhall.Tutorial (
    -- * Introduction
    -- $introduction

    -- * Types
    -- $types

    -- * Imports
    -- $imports

    -- * Functions
    -- $functions

    -- * Built-in functions
    -- $builtins

    -- ** Natural
    -- $natural

    -- * Total
    -- $total
    ) where

import Data.Vector (Vector)
import Dhall (Interpret(..), Type, detailed, input)

-- $introduction
--
-- The simplest way to use Dhall is to ignore the programming language features
-- and use it as a strongly typed configuration format.  For example, suppose
-- that you create the following configuration file:
-- 
-- > $ cat > config <<EOF
-- > < Example =
-- >     { foo = 1
-- >     , bar = [3.0, 4.0, 5.0] : List Double
-- >     }
-- > >
-- > EOF
-- 
-- You can read the above configuration file into Haskell using the following
-- code:
-- 
-- > -- example.hs
-- > 
-- > {-# LANGUAGE DeriveGeneric     #-}
-- > {-# LANGUAGE OverloadedStrings #-}
-- > 
-- > import Dhall
-- > 
-- > data Example = Example { foo :: Integer , bar :: Vector Double }
-- >     deriving (Generic, Show)
-- > 
-- > instance Interpret Example
-- > 
-- > main :: IO ()
-- > main = do
-- >     x <- input auto "./config"
-- >     print (x :: Example)
-- 
-- If you compile and run the above program, the program prints the
-- corresponding Haskell record:
-- 
-- > $ ./example
-- > Example {foo = 1, bar = [3.0,4.0,5.0]}
--
-- You can also load some types directly into Haskell without having to define a
-- record, like this:
--
-- > >>> :set -XOverloadedStrings
-- > >>> input auto "True" :: IO Bool
-- > True
--
-- The `input` function can decode any value if we specify the value's expected
-- `Type`:
--
-- > input
-- >     :: Type a
-- >     -> Text
-- >     -> IO a
--
-- ... and we can either specify an explicit type like `bool`:
--
-- > bool :: Type Bool
-- > 
-- > input bool :: Text -> IO Bool
-- >
-- > input bool "True" :: IO Bool
-- >
-- > >>> input bool "True"
-- > True
--
-- ... or we can use `auto` to let the compiler infer what type to decode from
-- the expected return type:
--
-- > auto :: Interpret a => Type a
-- >
-- > input auto :: Interpret a => Text -> IO a
-- >
-- > >>> input auto "True" :: IO Bool
-- > True
--
-- You can see what types `auto` supports \"out-of-the-box\" by browsing the
-- instances for the `Interpret` class.  For example, the following instance
-- says that we can directly decode any Dhall expression that evaluates to a
-- @Bool@ into a Haskell `Bool`:
--
-- > instance Interpret Bool
--
-- ... which is why we could directly decode the string @"True"@ into a Haskell
-- `Bool`.
--
-- There is also another instance that says that if we can decode a value of
-- type @a@, then we can also decode a @List@ of values as a `Vector` of @a@s:
--
-- > instance Interpret a => Interpret (Vector a)
--
-- Therefore, since we can decode a @Bool@, we must also be able to decode a
-- @List@ of @Bool@s.  Let's verify that this works, too:
--
-- > >>> input auto "[True, False] : List Bool" :: IO (Vector Bool)
-- > [True,False]
--
-- We could have also used an explicit `Type` instead of `auto`:
--
-- > >>> input (vector bool) "[True, False] : List Bool"
-- > [True, False]

-- $types
--
-- Suppose that we try to decode a value of the wrong type, like this:
--
-- > >>> input auto "1" :: IO Bool
-- > *** Exception: 
-- > Error: Expression doesn't match annotation
-- > 
-- > 1 : Bool
-- > 
-- > (input):1:1
--
-- The interpreter complains because the string @\"1\"@ cannot be decoded into a
-- Haskell value of type `Bool`.
--
-- The code excerpt from the above error message has two components:
--
-- * the expression being type checked (i.e. @1@)
-- * the expression's expected type (i.e. @Bool@)
--
-- > Expression
-- > ⇩
-- > 1 : Bool
-- >     ⇧
-- >     Expected type
--
-- The @:@ symbol is how Dhall annotates values with their expected types.
-- Whenever you see:
--
-- > x : t
--
-- ... you should read that as \"we expect the expression @x@ to have type
-- @t@\". However, we might be wrong and if our expected type does not match the
-- expression's actual type then the type checker will complain.
--
-- If you are familiar with other functional programming languages, this
-- notation is equivalent to type annotations in Haskell using the @(::)@
-- symbol.
--
-- In this case, the expression @1@ does not have type @Bool@ so type checking
-- fails with an exception.

-- $imports
--
-- You might wonder why in some cases we can decode a configuration file:
--
-- > >>> writeFile "bool" "True"
-- > >>> input auto "./bool" :: IO Bool
-- > True
--
-- ... and in other cases we can decode a value directly:
--
-- > >>> input auto "True" :: IO Bool
-- > True
--
-- This is because importing from a file is a special case of a more general
-- language feature: Dhall expressions can reference other expressions by their
-- file path.
--
-- To illustrate this, let's create three files:
-- 
-- > $ echo 'True'  > bool1
-- > $ echo 'False' > bool2
-- > $ echo './bool1 && ./bool2' > both
--
-- ... and read in all three files in a single expression:
-- 
-- > >>> input auto "[ ./bool1 , ./bool2 , ./both ] : List Bool" :: IO (Vector Bool)
-- > [True,False,False]
--
-- Each file path is replaced with the Dhall expression contained within that
-- file.  If that file contains references to other files then those references
-- are transitively resolved.
--
-- In other words: configuration files can reference other configuration files,
-- either by their relative or absolute paths.  This means that we can split a
-- configuration file into multiple files, like this:
--
-- > $ cat > config <<EOF
-- > < Example =
-- >   { foo = 1
-- >   , bar = ./bar
-- >   }
-- > >
-- > EOF
--
-- > $ cat > bar <<EOF
-- > [ 3.0, 4.0, 5.0 ] : List Double
-- > EOF
--
-- > $ ./example
-- > Example {foo = 1, bar = [3.0,4.0,5.0]}
--
-- However, the Dhall language will forbid cycles in these file references.  For
-- example, if we create the following cycle:
--
-- > $ echo './file1' > file2
-- > $ echo './file2' > file1
--
-- ... then the interpreter will reject the import:
--
-- > >>> input auto "./file1" :: IO Integer
-- > *** Exception: 
-- > ↳ ./file1
-- >   ↳ ./file2
-- >
-- > Cyclic import: ./file1
--
-- You can also import expressions by URL.  For example, you can find a Dhall
-- expression hosted at this URL using @ipfs@:
--
-- <https://ipfs.io/ipfs/QmVf6hhTCXc9y2pRvhUmLk3AZYEgjeAz5PNwjt1GBYqsVB>
--
-- > $ curl https://ipfs.io/ipfs/QmVf6hhTCXc9y2pRvhUmLk3AZYEgjeAz5PNwjt1GBYqsVB
-- > True
--
-- ... and you can reference that expression either directly:
--
-- > >>> input auto "https://ipfs.io/ipfs/QmVf6hhTCXc9y2pRvhUmLk3AZYEgjeAz5PNwjt1GBYqsVB" :: IO Bool
-- > True
-- 
-- ... or within a larger expression:
--
-- > >>> input auto "False == https://ipfs.io/ipfs/QmVf6hhTCXc9y2pRvhUmLk3AZYEgjeAz5PNwjt1GBYqsVB" :: IO Bool
-- > False
--
-- You're not limited to hosting Dhall expressions on @ipfs@.  You can host a
-- Dhall expression anywhere that you can host raw plaintext on the web, such as
-- Github, a pastebin, or your own web server.

-- $functions
--
-- The Dhall programming language also supports user-defined anonymous
-- functions.  For example, we can save the following anonymous function to a
-- file:
--
-- > $ cat > makeBools
-- > \(n : Bool) ->
-- >         [ n && True, n && False, n || True, n || False ] : List Bool
-- > <Ctrl-D>
--
-- ... or we can use Dhall's support for Unicode characters to use @λ@ instead of
-- @\\@ and @→@ instead of @->@ (for people who are into that sort of thing):
--
-- > $ cat > makeBools
-- > λ(n : Bool) →
-- >         [ n && True, n && False, n || True, n || False ] : List Bool
-- > <Ctrl-D>
--
-- You can read either one as a function of one argument named @n@ that has type
-- @Bool@.  This function returns a @List@ of @Bool@s.  Each element of the
-- @List@ depends on the input argument.
--
-- The (ASCII) syntax for anonymous functions resembles the syntax for anonymous
-- functions in Haskell.  The only difference is that Dhall requires you to
-- annotate the type of the function's input.
--
-- We can test our @makeBools@ function without having to modify and recompile
-- our Haskell program.  This library comes with a command-line executable
-- program named @dhall@ that you can use to both type-check configuration files
-- and convert them to a normal form.  Our compiler takes a program on standard
-- input and then prints the program's type to standard error followed by the
-- program's normal form to standard output:
--
-- > $ dhall <<< "./makeBools"
-- > ∀(n : Bool) → List Bool
-- > 
-- > λ(n : Bool) → [n && True, n && False, n || True, n || False] : List Bool
--
-- The first line says that @makeBools@ is a function of one argument named @n@
-- that has type @Bool@ and the function returns a @List@ of @Bool@s.  The
-- second line is our program's normal form, which in this case happens to be
-- identical to our original program.
--
-- We can \"apply\" our file to a @Bool@ argument, like this:
--
-- > $ dhall <<< "./makeBools True"
-- > List Bool
-- > 
-- > [True, False, True, True] : List Bool
--
-- Remember that file paths are synonymous with their contents, so the above
-- code is equivalent to:
-- 
-- > $ dhall <<< "(λ(n : Bool) → [n && True, n && False, n || True, n || False] : List Bool) True"
-- > List Bool
-- > 
-- > [True, False, True, True] : List Bool
--
-- Functions are separated from their arguments by whitespace.  So if you see:
--
-- @f x@
--
-- ... you should read that as \"apply the function @f@ to the argument @x@\".
--
-- When you apply an anonymous function to an argument, you substitute the
-- \"bound variable" with the function's argument:
--
-- >    Bound variable
-- >    ⇩
-- > (λ(n : Bool) → ...) True
-- >                     ⇧
-- >                     Function argument
--
-- So in our above example, we would replace all occurrences of @n@ with @True@,
-- like this:
--
-- > -- If we replace all of these `n`s with `True` ...
-- > [n && True, n && False, n || True, n || False] : List Bool
-- >
-- > -- ... then we get this:
-- > [True && True, True && False, True || True, True || False] : List Bool
-- >
-- > -- ... which reduces to the following normal form:
-- > [True, False, True, True] : List Bool
--
-- Now that we've verified that our function type checks and works, we can use
-- the same function within Haskell:
--
-- > >>> input auto "./makeBools True" :: IO (Vector Bool)
-- > [True,False,True,True]

-- $builtins
--
-- Dhall is a restricted programming language that only supports simple built-in
-- functions and operators.  If you wish to do anything fancier you will need to
-- load your data into Haskell for further processing
--
-- The language provides support for the following primitive types:
--
-- * @Bool@ values
-- * @Natural@ values
-- * @Integer@ values
-- * @Double@ values
-- * @Text@ values
--
-- ... as well as support for the following derived types:
--
-- * @List@s of values
-- * @Optional@ values
-- * Anonymous records
-- * Anonymous unions
--
-- Each of the following sections provides an overview of builtin functions and
-- operators for each type.  For each function you get:
--
-- * An example use of that function
--
-- * A \"type judgement\" explaining when that function or operator is well
--   typed
--
-- For example, for the following judgement:
--
-- > Γ ⊢ x : Natural   Γ ⊢ y : Natural
-- > ────────────────────────────────
-- > Γ ⊢ x + y : Natural
--
-- ... you can read that as saying: "if @x@ has type @Natural@ and @y@ has type
-- @Natural@, then @x + y@ has type @Natural@"
--
-- Similarly, for the following judgement:
--
-- > ─────────────────────────────────
-- > Γ ⊢ Natural/even : Natural → Bool
--
-- ... you can read that as saying: "@Natural/even@ always has type
-- @Natural → Bool@"
--
-- * Rules for how that function or operator behaves
--
-- These rules are just equalities that come in handy when reasoning about code.
-- For example, the section on addition has the following rules:
--
-- > (x + y) + z = x + (y + z)
-- >
-- > x + +0 = x
-- >
-- > +0 + x = x
--
-- These rules are also a contract for how the compiler should behave.  If you
-- ever observe code that does not obey these rules you should file a bug
-- report.

-- $natural
--
-- For example, Dhall only supports addition and multiplication on @Natural@
-- numbers (i.e. non-negative numbers), which are not the same type of number as
-- @Integer@s (which can be negative).  A @Natural@ number is a number prefixed
-- with the @+@ symbol.  If you try to add or multiply two @Integer@s (without
-- the @+@ prefix) you will get a type error:
--
-- > $ dhall
-- > 2 + 2
-- > <Ctrl-D>
-- > Use "dhall --explain" for detailed errors
-- > 
-- > Error: ❰+❱ only works on ❰Natural❱s
-- > 
-- > 2 + 2
-- > 
-- > (stdin):1:1
--
-- In fact, there are no built-in functions for @Integer@s (or @Double@s).  As
-- far as the language is concerned they are opaque values that can only be
-- shuffled around but not used in any meaningful way until they have been
-- loaded into Haskell.
--
-- You can do useful things with @Natural@ numbers, though.  The built-in
-- functions and operations are:
--
-- * Addition:
--
-- Example:
--
-- > $ dhall
-- > +2 + +3
-- > <Ctrl-D>
-- > Natural
-- > 
-- > +5
--
-- Type:
--
-- > Γ ⊢ x : Natural   Γ ⊢ y : Natural
-- > ────────────────────────────────
-- > Γ ⊢ x + y : Natural
--
-- Rules:
--
-- > (x + y) + z = x + (y + z)
-- >
-- > x + +0 = x
-- >
-- > +0 + x = x
--
-- * Multiplication
--
-- Example:
--
-- > $ dhall
-- > +2 * +3
-- > <Ctrl-D>
-- > Natural
-- > 
-- > +6
--
-- Type:
--
-- > Γ ⊢ x : Natural   Γ ⊢ y : Natural
-- > ────────────────────────────────
-- > Γ ⊢ x * y : Natural
--
-- Rules:
--
-- > (x * y) * z = x * (y * z)
-- >
-- > x * +1 = x
-- >
-- > +1 * x = x
-- >
-- > (x + y) * z = (x * z) + (y * z)
-- >
-- > x * (y + z) = (x * y) + (x * z)
-- >
-- > x * +0 = +0
-- >
-- > +0 * x = +0
--
-- * Even
--
-- Example:
--
-- > $ dhall
-- > Natural/even +6
-- > <Ctrl-D>
-- > Bool
-- > 
-- > True
--
-- Type:
--
-- > ─────────────────────────────────
-- > Γ ⊢ Natural/even : Natural → Bool
--
-- Rules:
--
-- > Natural/even (x + y) = Natural/even x == Natural/even y
-- >
-- > Natural/even +0 = True
-- >
-- > Natural/even (x * y) = Natural/even x || Natural/even y
-- >
-- > Natural/even +1 = False
--
-- * Odd
--
-- Example:
--
-- > $ dhall
-- > Natural/odd +6
-- > <Ctrl-D>
-- > Bool
-- > 
-- > False
--
-- Type:
--
-- > ────────────────────────────────
-- > Γ ⊢ Natural/odd : Natural → Bool
--
-- Rules:
--
-- > Natural/odd (x + y) = Natural/odd x /= Natural/odd y
-- >
-- > Natural/odd +0 = False
-- >
-- > Natural/odd (x * y) = Natural/odd x && Natural/odd y
-- >
-- > Natural/odd +1 = True
--
-- * Test for zero
--
-- Example:
--
-- > $ dhall
-- > Natural/isZero +6
-- > <Ctrl-D>
-- > Bool
-- > 
-- > False
--
-- Type:
--
-- > ───────────────────────────────────
-- > Γ ⊢ Natural/isZero : Natural → Bool
--
-- Rules:
--
-- > Natural/isZero (x + y) = Natural/isZero x && Natural/isZero y
-- >
-- > Natural/isZero +0 = True
-- >
-- > Natural/isZero (x * y) = Natural/isZero x || Natural/isZero y
-- >
-- > Natural/isZero +1 = False
--
-- * Folding
--
-- Example:
--
-- > $ dhall
-- > Natural/fold +40 Text (λ(t : Text) → t ++ "!") "You're welcome"
-- > <Ctrl-D>
-- > Text
-- > 
-- > "You're welcome!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
--
-- Type:
--
-- > ──────────────────────────────────────────────────────────
-- > Γ ⊢ Natural/fold : Natural → ∀(a : Type) → (a → a) → a → a
--
-- Rules:
-- 
-- > Natural/fold (x + y) n s z = Natural/fold x n s (Natural/fold y n s z)
-- > 
-- > Natural/fold +0 n s z = z
-- > 
-- > Natural/fold (x * y) n s = Natural/fold x n (Natural/fold y n s)
-- > 
-- > Natural/fold 1 n s = s
--
-- * Building
--
-- Example:
--
-- > $ dhall
-- > Natural/build (λ(a : Type) → λ(succ : a → a) → λ(zero : a) → succ (succ zero))
-- > Natural
-- > 
-- > +2
--
-- Type:
--
-- > ─────────────────────────────────────────────────────────────
-- > Γ ⊢ Natural/build : (∀(a : Type) → (a → a) → a → a) → Natural
--
-- Rules:
--
-- > Natural/fold (Natural/build x) = x
-- >
-- > Natural/build (Natural/fold x) = x

-- $total
--
-- Dhall is a total programming language, which means that Dhall is not
-- Turing-complete and evaluation of every Dhall program is guaranteed to
-- eventually halt.  There is no upper bound on how long the program might take
-- to evaluate, but the program is guaranteed to terminate in a finite amount of
-- time and not hang forever.
--
-- This guarantees that all Dhall programs can be safely reduced to a normal
-- form where all functions have been evaluated.  In fact, Dhall expressions can
-- be evaluated even if all function arguments haven't been fully applied.  For
-- example, the following program is an anonymous function:
--
-- > $ dhall
-- > \(n : Bool) -> +10 * +10
-- > <Ctrl-D>
-- > ∀(n : Bool) → Natural
-- > 
-- > λ(n : Bool) → +100
--
-- ... and even though the function is still missing the first argument named
-- @n@ the compiler is smart enough to evaluate the body of the anonymous
-- function ahead of time before the function has even been invoked.
