module Lib
    ( readExpr, eval
    ) where

import Text.ParserCombinators.Parsec hiding (spaces)
import Control.Monad
import Control.Monad.Error

data SchemeVal 
    = Atom String
    | List [SchemeVal]
    | Bool Bool
    | Number Double
    | String String


unwordsList :: [SchemeVal] -> String
unwordsList = unwords . map showVal

showVal :: SchemeVal -> String
showVal (String str) = "\"" ++ str ++ "\""
showVal (Atom name) = name
showVal (Number num) = show num
showVal (Bool True) = "True"
showVal (Bool False) = "False"
showVal (List contents) = "(" ++ unwordsList contents ++ ")"

instance Show SchemeVal where show = showVal

symbol :: Parser Char
symbol = oneOf "!#$%&|*+-/:<=>?@^_~"

spaces :: Parser ()
spaces = skipMany1 space

parseAtom :: Parser SchemeVal
parseAtom = do
    first <- letter <|> symbol
    rest <- many (letter <|> digit <|> symbol)
    let atom = first:rest
    return $ case atom of 
        "True" -> Bool True
        "False" -> Bool False
        _    -> Atom atom

parseInteger :: Parser SchemeVal
parseInteger = liftM (Number . \x -> read x :: Double) (many1 digit)

parseDouble :: Parser SchemeVal
parseDouble = do
    x <- many1 digit
    char '.'
    y <- many1 digit
    return $ Number (read (x ++ ['.'] ++ y) :: Double)

parseNumber :: Parser SchemeVal
parseNumber = try parseDouble <|> parseInteger

parseString :: Parser SchemeVal
parseString = do
    char '"'
    x <- many (noneOf "\"")
    char '"'
    return $ String x

parseList :: Parser SchemeVal
parseList = liftM List (sepBy parseExpr spaces)

parseExpr :: Parser SchemeVal
parseExpr = parseAtom
    <|> parseString
    <|> parseNumber
    <|> do
            char '('
            x <- parseList
            char ')'
            return x

primitives :: [(String, [SchemeVal] -> SchemeVal)]
primitives = [("+", numericBinop (+)),
              ("-", numericBinop (-)),
              ("*", numericBinop (*)),
              ("/", numericBinop (/))]

apply :: String -> [SchemeVal] -> SchemeVal
apply func args = maybe (Bool False) ($ args) $ lookup func primitives

numericBinop :: (Double -> Double -> Double) -> [SchemeVal] -> SchemeVal
numericBinop op params = Number $ foldl1 op $ map unpackNum params

unpackNum :: SchemeVal -> Double
unpackNum (Number n) = n
unpackNum (String n) = let parsed = reads n :: [(Double, String)] in 
                           if null parsed 
                              then 0
                              else fst $ parsed !! 0
unpackNum (List [n]) = unpackNum n
unpackNum _ = 0

eval :: SchemeVal -> SchemeVal
eval val@(Atom _) = val
eval val@(String _) = val
eval val@(Number _) = val
eval val@(Bool _) = val
eval (List (Atom func : args)) = apply func $ map eval args

readExpr :: String -> SchemeVal
readExpr input = case parse parseExpr "lisp" input of
    Left err -> String $ "No match: " ++ show err
    Right val -> val
