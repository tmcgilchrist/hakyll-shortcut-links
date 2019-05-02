{-# LANGUAGE FlexibleContexts #-}

{- |
Copyright:  (c) 2019 Kowainik
License:    MPL-2.0
Maintainer: Kowainik <xrom.xkov@gmail.com>

This package allows to use [shortcut-links](https://hackage.haskell.org/package/shortcut-links)
package in websites generated by [hakyll](https://hackage.haskell.org/package/hakyll).

The flexible interface allows to use the supported huge collection of shortcuts
along with using custom ones.

-}

module Hakyll.ShortcutLinks
       ( -- * Pandoc functions
         -- $pandoc
         applyShortcuts
       , applyAllShortcuts

         -- * Hakyll functions
         -- $hakyll
       , shortcutLinksCompiler
       , allShortcutLinksCompiler

         -- * Shortcut-links reexports
         -- $sh
       , module Sh
         -- $allSh
       , module ShortcutLinks.All
       ) where

import Control.Monad.Except (MonadError (..))
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Hakyll (Compiler, Item, defaultHakyllReaderOptions, defaultHakyllWriterOptions,
               pandocCompilerWithTransformM)
import ShortcutLinks (Result (..), Shortcut, allShortcuts, useShortcutFrom)
import Text.Pandoc.Generic (bottomUpM)

import Hakyll.ShortcutLinks.Parser (parseShortcut)

-- exports
import ShortcutLinks as Sh
import ShortcutLinks.All

import qualified Data.Text as T
import qualified Text.Pandoc.Definition as Pandoc


{- $pandoc
Functions to transform 'Pandoc.Pandoc' documents. These functions modify
markdown links to the extended links.

These are the most generic functions. They work inside the monad @m@ that has
@'MonadError' ['String']@ instance.
You can use the pure version of these function because there's 'MonadError'
instance for 'Either':

@
applyShorcuts :: [(['Text'], 'Shortcut')] -> 'Pandoc.Pandoc' -> 'Either' ['String'] 'Pandoc.Pandoc'
applyAllShorcuts :: 'Pandoc.Pandoc' -> 'Either' ['String'] 'Pandoc.Pandoc'
@

If you have your own @hakyll@ options for your custom pandoc compiler, you can
use this function like this:

@
'pandocCompilerWithTransformM'
    myHakyllReaderOptions
    myHakyllWriterOptions
    ('applyShortcuts' myShortcuts)
@


-}

{- | Modifies markdown shortcut links to the extended version and returns
'Pandoc.Pandoc' with the complete links instead.

Unlike 'applyAllShortcuts' which uses the hardcoded list of the possible
shortcuts (see 'allShortcuts'), the 'applyShortcuts' function uses the given
list of custom provided shortcuts.
For your help you can use 'ShortcutLinks.All' module to see all available
shortcuts.

If you want to add a couple of custom shortcuts to the list of already existing
shortcuts you can do it in the following way:

@
(["hk", "hackage"], 'hackage') : 'allShortcuts'
@
-}
applyShortcuts
    :: forall m . MonadError [String] m
    => [([Text], Shortcut)]  -- ^ Shortcuts
    -> Pandoc.Pandoc         -- ^ Pandoc document that possibly contains shortened links
    -> m Pandoc.Pandoc       -- ^ Result pandoc document with shorcuts expanded
applyShortcuts shortcuts = bottomUpM applyLink
  where
    applyLink :: Pandoc.Inline -> m Pandoc.Inline
    applyLink l@(Pandoc.Link attr inl (url, title)) = case parseShortcut $ T.pack url of
        Right (name, option, text) -> checkTitle inl >>= \txtTitle ->
            case useShortcutFrom shortcuts name option $ fromMaybe txtTitle text of
                Success link -> pure $ Pandoc.Link attr inl (T.unpack link, title)
                Warning ws _ -> throwError ws
                Failure msg  -> throwError [msg]
        Left _ -> pure l  -- the link is not shortcut
    applyLink other = pure other

    checkTitle :: [Pandoc.Inline] -> m Text
    checkTitle = \case
        [] -> throwError ["Empty shortcut link title arguments"]
        [Pandoc.Str s] -> pure $ T.pack s
        _ -> throwError ["Shortcut title is not a single string element"]

{- |  Modifies markdown shortcut links to the extended version and returns
'Pandoc.Pandoc' with the complete links instead.

Similar to 'applyShortcuts' but uses 'allShortcuts' as a list of shortcuts to
parse against.
-}
applyAllShortcuts :: MonadError [String] m => Pandoc.Pandoc -> m Pandoc.Pandoc
applyAllShortcuts = applyShortcuts allShortcuts

{- $hakyll
Functions to integrate shortcut links to [hakyll](http://hackage.haskell.org/package/hakyll).

@hakyll-shortcut-links@ provides out-of-the-box 'Compiler's that translate
markdown documents with shortcut links into the documents with extended links.

Usually you would want to use this feature on your blog post markdown files.
Assuming that you already have similar code for it:

@
match "blog/*" $ do
    route $ setExtension "html"
    compile $
        __pandocCompiler__
            >>= loadAndApplyTemplate "templates/post.html" defaultContext
            >>= relativizeUrls
@

All that you would need to do is to replace 'Hakyll.pandocCompiler' with
'shortcutLinksCompiler' or 'allShortcutLinksCompiler':

@
match "blog/*" $ do
    route $ setExtension "html"
    compile $
        __'allShortcutLinksCompiler'__
            >>= loadAndApplyTemplate "templates/post.html" defaultContext
            >>= relativizeUrls
@

-}

{- | Our own pandoc compiler which parses shortcut links automatically.
It takes a custom list of shortcut links to be used in the document.
-}
shortcutLinksCompiler :: [([Text], Shortcut)] -> Compiler (Item String)
shortcutLinksCompiler = pandocCompilerWithTransformM
    defaultHakyllReaderOptions
    defaultHakyllWriterOptions
    . applyShortcuts

{- | Our own pandoc compiler which parses shortcut links automatically. Same as
'shortcutLinksCompiler' but passes 'allShortcuts' as an argument.
-}
allShortcutLinksCompiler :: Compiler (Item String)
allShortcutLinksCompiler = shortcutLinksCompiler allShortcuts

{- $sh
This is the module from @shortcut-links@ library that introduces the functions
that by given shortcuts creates the 'Result'ing URL (if possible).
-}

{- $allSh
This module stores a large number of supported 'Shortcut's.
It also reexports a useful function 'allShortcuts' that is a list of all
shortcuts, together with suggested names for them.

In @hakyll-shortcut-links@ we are exporting both functions that work with the
standard list of 'allShortcuts', but also we provide the option to use your own
lists of shortcuts (including self-created ones).

For example, if you want to use just 'github' and 'hackage' shortcuts you can
create the following list:

@
(["github"], github) : (["hackage"], hackage) : []
@

If you want to create your own shortcut that is not included in
"ShortcutLinks.All" module you can achieve that implementing the following
function:

@
kowainik :: 'Shortcut'
kowainik _ text = pure $ "https://kowainik.github.io/posts/" <> text

myShortcuts :: [(['Text'], 'Shortcut')]
myShortcuts = [(["kowainik"], kowainik)]
@

And it would work like this:

@
[blog post]\(@kowainik:2019-02-06-style-guide)

=>

[blog post]\(https:\/\/kowainik.github.io\/posts\/2019-02-06-style-guide)
@
-}
