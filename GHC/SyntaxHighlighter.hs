{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TupleSections     #-}

module GHC.SyntaxHighlighter
  ( Token (..)
  , tokenizeHaskell )
where

import Control.Monad
import Data.List (unfoldr)
import Data.Text (Text)
import FastString (mkFastString)
import Module (newSimpleUnitId, ComponentId (..))
import SrcLoc
import StringBuffer
import qualified Data.Text as T
import qualified EnumSet   as ES
import qualified Lexer     as L

----------------------------------------------------------------------------
-- Data types

-- | Token types that are used as tags to mark spans of source code.

data Token
  = KeywordTok         -- ^ Keyword
  | PragmaTok          -- ^ Pragmas
  | SymbolTok          -- ^ Symbols (punctuation that is not an operator)
  | VariableTok        -- ^ Variable name (term level)
  | ConstructorTok     -- ^ Data\/type constructor
  | OperatorTok        -- ^ Operator
  | CharTok            -- ^ Character
  | StringTok          -- ^ String
  | IntegerTok         -- ^ Integer
  | RationalTok        -- ^ Rational number
  | CommentTok         -- ^ Comment (including Haddocks)
  | SpaceTok           -- ^ Space filling
  | OtherTok           -- ^ Something else?
  deriving (Eq, Ord, Enum, Bounded, Show)

-- | Internal type containing line\/column combinations for start and end
-- positions of a code span.

data Loc = Loc !Int !Int !Int !Int
  deriving (Show)

----------------------------------------------------------------------------
-- High-level API

-- | Tokenize Haskell source code. If the code cannot be parsed, return
-- 'Nothing'. Otherwise return the original input tagged by 'Token's.

tokenizeHaskell :: Text -> Maybe [(Token, Text)] -- [(Token, Loc)]
tokenizeHaskell input =
  case L.unP pLexer parseState of
    L.PFailed {} -> Nothing
    L.POk    _ x -> Just (sliceInputStream input x)
  where
    location = mkRealSrcLoc (mkFastString "") 1 1
    buffer = stringToStringBuffer (T.unpack input)
    parseState = L.mkPStatePure parserFlags buffer location
    parserFlags = L.ParserFlags
      { L.pWarningFlags = ES.empty
      , L.pExtensionFlags = ES.empty
      , L.pThisPackage = newSimpleUnitId (ComponentId (mkFastString ""))
      , L.pExtsBitmap = maxBound -- allow all that fancy stuff
      }

-- | Haskell lexer.

pLexer :: L.P [(Token, Loc)]
pLexer = go
  where
    go = do
      r <- L.lexer False return
      case r of
        L _ L.ITeof -> return []
        _           ->
          case fixupToken r of
            Nothing -> go
            Just  x -> (x:) <$> go

-- | Replace 'Loc' locations with actual chunks of input 'Text'.

sliceInputStream :: Text -> [(Token, Loc)] -> [(Token, Text)]
sliceInputStream input toks = unfoldr sliceOnce (initText' input, toks)
  where
    sliceOnce (_, []) = Nothing
    sliceOnce (txt, tss@((t, l):ts)) =
      case tryFetchSpace txt l of
        Nothing ->
          let (txt', chunk) = fetchSpan txt l
          in Just ((t, chunk), (txt', ts))
        Just (txt', chunk) ->
          Just ((SpaceTok, chunk), (txt', tss))

-- | Convert @'Located' 'L.Token'@ representation to a more convenient for
-- us form.

fixupToken :: Located L.Token -> Maybe (Token, Loc)
fixupToken (L srcSpan tok) = (classifyToken tok,) <$> srcSpanToLoc srcSpan

-- | Convert 'SrcSpan' to 'Loc'.

srcSpanToLoc :: SrcSpan -> Maybe Loc
srcSpanToLoc (RealSrcSpan rss) =
  let start = realSrcSpanStart rss
      end   = realSrcSpanEnd   rss
  in Just $ Loc (srcLocLine start)
                (srcLocCol start)
                (srcLocLine end)
                (srcLocCol end)
srcSpanToLoc _ = Nothing

-- | Classify a 'L.Token' in terms of 'Token'.

classifyToken :: L.Token -> Token
classifyToken = \case
  -- Keywords
  L.ITas        -> KeywordTok
  L.ITcase      -> KeywordTok
  L.ITclass     -> KeywordTok
  L.ITdata      -> KeywordTok
  L.ITdefault   -> KeywordTok
  L.ITderiving  -> KeywordTok
  L.ITdo        -> KeywordTok
  L.ITelse      -> KeywordTok
  L.IThiding    -> KeywordTok
  L.ITforeign   -> KeywordTok
  L.ITif        -> KeywordTok
  L.ITimport    -> KeywordTok
  L.ITin        -> KeywordTok
  L.ITinfix     -> KeywordTok
  L.ITinfixl    -> KeywordTok
  L.ITinfixr    -> KeywordTok
  L.ITinstance  -> KeywordTok
  L.ITlet       -> KeywordTok
  L.ITmodule    -> KeywordTok
  L.ITnewtype   -> KeywordTok
  L.ITof        -> KeywordTok
  L.ITqualified -> KeywordTok
  L.ITthen      -> KeywordTok
  L.ITtype      -> KeywordTok
  L.ITwhere     -> KeywordTok
  L.ITforall _  -> KeywordTok
  L.ITexport    -> KeywordTok
  L.ITlabel     -> KeywordTok
  L.ITdynamic   -> KeywordTok
  L.ITsafe      -> KeywordTok
  L.ITinterruptible -> KeywordTok
  L.ITunsafe    -> KeywordTok
  L.ITstdcallconv -> KeywordTok
  L.ITccallconv -> KeywordTok
  L.ITcapiconv  -> KeywordTok
  L.ITprimcallconv -> KeywordTok
  L.ITjavascriptcallconv -> KeywordTok
  L.ITmdo       -> KeywordTok
  L.ITfamily    -> KeywordTok
  L.ITrole      -> KeywordTok
  L.ITgroup     -> KeywordTok
  L.ITby        -> KeywordTok
  L.ITusing     -> KeywordTok
  L.ITpattern   -> KeywordTok
  L.ITstatic    -> KeywordTok
  L.ITstock     -> KeywordTok
  L.ITanyclass  -> KeywordTok
  L.ITunit      -> KeywordTok
  L.ITsignature -> KeywordTok
  L.ITdependency -> KeywordTok
  L.ITrequires  -> KeywordTok
  -- Pragmas
  L.ITinline_prag {} -> PragmaTok
  L.ITspec_prag _ -> PragmaTok
  L.ITspec_inline_prag {} -> PragmaTok
  L.ITsource_prag _ -> PragmaTok
  L.ITrules_prag _ -> PragmaTok
  L.ITwarning_prag _ -> PragmaTok
  L.ITdeprecated_prag _ -> PragmaTok
  L.ITline_prag _ -> PragmaTok
  L.ITcolumn_prag _ -> PragmaTok
  L.ITscc_prag _ -> PragmaTok
  L.ITgenerated_prag _ -> PragmaTok
  L.ITcore_prag _ -> PragmaTok
  L.ITunpack_prag _ -> PragmaTok
  L.ITnounpack_prag _ -> PragmaTok
  L.ITann_prag _ -> PragmaTok
  L.ITcomplete_prag _ -> PragmaTok
  L.ITclose_prag -> PragmaTok
  L.IToptions_prag _ -> PragmaTok
  L.ITinclude_prag _ -> PragmaTok
  L.ITlanguage_prag -> PragmaTok
  L.ITvect_prag _ -> PragmaTok
  L.ITvect_scalar_prag _ -> PragmaTok
  L.ITnovect_prag _ -> PragmaTok
  L.ITminimal_prag _ -> PragmaTok
  L.IToverlappable_prag _ -> PragmaTok
  L.IToverlapping_prag _ -> PragmaTok
  L.IToverlaps_prag _ -> PragmaTok
  L.ITincoherent_prag _ -> PragmaTok
  L.ITctype _ -> PragmaTok
  -- Reserved symbols
  L.ITdotdot -> SymbolTok
  L.ITcolon -> SymbolTok
  L.ITdcolon _ -> SymbolTok
  L.ITequal -> SymbolTok
  L.ITlam -> SymbolTok
  L.ITlcase -> SymbolTok
  L.ITvbar -> SymbolTok
  L.ITlarrow _ -> SymbolTok
  L.ITrarrow _ -> SymbolTok
  L.ITat -> SymbolTok
  L.ITtilde -> SymbolTok
  L.ITtildehsh -> SymbolTok
  L.ITdarrow _ -> SymbolTok
  L.ITbang -> SymbolTok
  L.ITbiglam -> SymbolTok
  L.ITocurly -> SymbolTok
  L.ITccurly -> SymbolTok
  L.ITvocurly -> SymbolTok
  L.ITvccurly -> SymbolTok
  L.ITobrack -> SymbolTok
  L.ITopabrack -> SymbolTok
  L.ITcpabrack -> SymbolTok
  L.ITcbrack -> SymbolTok
  L.IToparen -> SymbolTok
  L.ITcparen -> SymbolTok
  L.IToubxparen -> SymbolTok
  L.ITcubxparen -> SymbolTok
  L.ITsemi -> SymbolTok
  L.ITcomma -> SymbolTok
  L.ITunderscore -> SymbolTok
  L.ITbackquote -> SymbolTok
  L.ITsimpleQuote -> SymbolTok
  -- NOTE GHC thinks these are reserved symbols, but I classify them as
  -- operators.
  L.ITminus -> OperatorTok
  L.ITdot -> OperatorTok
  -- Identifiers
  L.ITvarid _ -> VariableTok
  L.ITconid _ -> ConstructorTok
  L.ITvarsym _ -> OperatorTok
  L.ITconsym _ -> OperatorTok
  L.ITqvarid _ -> VariableTok
  L.ITqconid _ -> ConstructorTok
  L.ITqvarsym _ -> OperatorTok
  L.ITqconsym _ -> OperatorTok
  L.ITdupipvarid _ -> VariableTok
  L.ITlabelvarid _ -> VariableTok
  -- Basic types
  L.ITchar _ _ -> CharTok
  L.ITstring _ _ -> StringTok
  L.ITinteger _ -> IntegerTok
  L.ITrational _ -> RationalTok
  L.ITprimchar _ _ -> CharTok
  L.ITprimstring _ _ -> StringTok
  L.ITprimint _ _ -> IntegerTok
  L.ITprimword _ _ -> IntegerTok
  L.ITprimfloat _ -> RationalTok
  L.ITprimdouble _ -> RationalTok
  -- Template Haskell extension tokens
  L.ITopenExpQuote _ _ -> SymbolTok
  L.ITopenPatQuote -> SymbolTok
  L.ITopenDecQuote -> SymbolTok
  L.ITopenTypQuote -> SymbolTok
  L.ITcloseQuote _ -> SymbolTok
  L.ITopenTExpQuote _ -> SymbolTok
  L.ITcloseTExpQuote -> SymbolTok
  L.ITidEscape _ -> SymbolTok
  L.ITparenEscape -> SymbolTok
  L.ITidTyEscape _ -> SymbolTok
  L.ITparenTyEscape -> SymbolTok
  L.ITtyQuote -> SymbolTok
  L.ITquasiQuote _ -> SymbolTok
  L.ITqQuasiQuote _ -> SymbolTok
  -- Arrow notation
  L.ITproc -> KeywordTok
  L.ITrec -> KeywordTok
  L.IToparenbar _ -> SymbolTok
  L.ITcparenbar _ -> SymbolTok
  L.ITlarrowtail _ -> SymbolTok
  L.ITrarrowtail _ -> SymbolTok
  L.ITLarrowtail _ -> SymbolTok
  L.ITRarrowtail _ -> SymbolTok
  -- Type application
  L.ITtypeApp -> SymbolTok
  -- Special
  L.ITunknown _ -> OtherTok
  L.ITeof -> OtherTok -- normally is not included in results
  -- Documentation annotations
  L.ITdocCommentNext _ -> CommentTok
  L.ITdocCommentPrev _ -> CommentTok
  L.ITdocCommentNamed _ -> CommentTok
  L.ITdocSection _ _ -> CommentTok
  L.ITdocOptions _ -> CommentTok
  L.ITlineComment _ -> CommentTok
  L.ITblockComment _ -> CommentTok

----------------------------------------------------------------------------
-- Text traversing

-- | A type for 'Text' with line\/column location attached.

data Text' = Text'
  {-# UNPACK #-} !Int
  {-# UNPACK #-} !Int
  {-# UNPACK #-} !Text
  deriving (Show)

-- | Create 'Text' from 'Text''.

initText' :: Text -> Text'
initText' = Text' 1 1

-- | Try to fetch white space before start of span at 'Loc'.

tryFetchSpace :: Text' -> Loc -> Maybe (Text', Text)
tryFetchSpace txt (Loc sl sc _ _) =
  let (txt', r) = reachLoc txt sl sc
  in if T.null r
       then Nothing
       else Just (txt', r)

-- | Fetch span at 'Loc'.

fetchSpan :: Text' -> Loc -> (Text', Text)
fetchSpan txt (Loc _ _ el ec) = reachLoc txt el ec

-- | Reach given line\/column location and return 'Text' that has been
-- traversed.

reachLoc
  :: Text'
  -> Int               -- ^ Line number to reach
  -> Int               -- ^ Column number to reach
  -> (Text', Text)
reachLoc txt@(Text' _ _ original) l c =
  let chunk = T.unfoldr f txt
      f (Text' l' c' s) = do
        (ch, s') <- T.uncons s
        let (l'', c'') = case ch of
              '\n' -> (l' + 1, 1)
              '\t' -> (l', c' + 8 - ((c' - 1) `rem` 8))
              _    -> (l', c' + 1)
        guard (l'' < l || c'' <= c)
        return (ch, Text' l'' c'' s')
  in (Text' l c (T.drop (T.length chunk) original), chunk)