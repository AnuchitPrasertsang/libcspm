module CSPM.Parser.Exceptions (
    invalidPatternErrorMessage,
    invalidLetDeclarationErrorMessage,
    invalidModuleDeclarationErrorMessage,
    invalidExpressionErrorMessage,
    invalidIncludeErrorMessage,
    invalidTimedSectionDeclarationErrorMessage,
    lexicalErrorMessage,
    parseErrorMessage,
    fileAccessErrorMessage,
    
    throwSourceError
)
where

import CSPM.DataStructures.Syntax
import CSPM.Parser.Tokens
import CSPM.PrettyPrinter
import Util.Annotated
import Util.Exception
import Util.PrettyPrint

invalidPatternErrorMessage :: PExp -> ErrorMessage
invalidPatternErrorMessage e = mkErrorMessage (loc e) $
    hang (prettyPrint e) tabWidth (text "is not a valid pattern")
    
invalidLetDeclarationErrorMessage :: PDecl -> ErrorMessage
invalidLetDeclarationErrorMessage d = mkErrorMessage (loc d) $
    hang (prettyPrint d) tabWidth (text "is not a valid declaration in a let expression")

invalidModuleDeclarationErrorMessage :: PDecl -> ErrorMessage
invalidModuleDeclarationErrorMessage d = mkErrorMessage (loc d) $
    hang (prettyPrint d) tabWidth (text "is not a valid declaration in a module")

invalidTimedSectionDeclarationErrorMessage :: PDecl -> ErrorMessage
invalidTimedSectionDeclarationErrorMessage d = mkErrorMessage (loc d) $
    hang (prettyPrint d) tabWidth (text "is not a valid declaration in a timed section")

invalidExpressionErrorMessage :: PExp -> ErrorMessage
invalidExpressionErrorMessage e = mkErrorMessage (loc e) $
    hang (prettyPrint e) tabWidth (text "is not a valid expression")

invalidIncludeErrorMessage :: SrcSpan -> ErrorMessage
invalidIncludeErrorMessage srcspan = 
    mkErrorMessage srcspan (text "Invalid include directive")

lexicalErrorMessage :: SrcSpan -> ErrorMessage
lexicalErrorMessage srcspan = mkErrorMessage srcspan (text "Lexical error")

parseErrorMessage :: LToken -> ErrorMessage
parseErrorMessage tok = mkErrorMessage (locatedLoc tok) $
    text "Unexpected token" <+> prettyPrint tok

fileAccessErrorMessage :: FilePath -> ErrorMessage
fileAccessErrorMessage fp = mkErrorMessage Unknown $
    text "Could not open the file" <+> quotes (text fp)
