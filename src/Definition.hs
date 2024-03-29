module Definition where

import Text.ParserCombinators.Parsec
import Control.Monad.Except
import Data.IORef

data SchemeVal 
    = Symbol String
    | List [SchemeVal]
    | Bool Bool
    | Number Double
    | String String
    | PrimitiveFunc ([SchemeVal] -> ThrowsError SchemeVal)
    | Func { params :: [String], vararg :: (Maybe String), body :: [SchemeVal], closure :: Env }

unwordsList :: [SchemeVal] -> String
unwordsList = unwords . map show

instance Show SchemeVal where
    show (String str) = "\"" ++ str ++ "\""
    show (Symbol name) = name
    show (Number num) = show num
    show (Bool True) = "True"
    show (Bool False) = "False"
    show (List contents) = "(" ++ unwordsList contents ++ ")"
    show (PrimitiveFunc _) = "<primitive>"
    show (Func {params = args, vararg = varargs, body = body, closure = env}) =
        "(lambda (" ++ unwords (map show args) ++
            (case varargs of
                Nothing -> ""
                Just arg -> " . " ++ arg) ++ ") ...)"

data SchemeError
    = NumArgs Integer [SchemeVal]
    | TypeMismatch String SchemeVal
    | Parser ParseError
    | BadSpecialForm String SchemeVal
    | NotFunction String String
    | UnboundVar String String
    | Default String

instance Show SchemeError where
    show (UnboundVar message varname)  = message ++ ": " ++ varname
    show (BadSpecialForm message form) = message ++ ": " ++ show form
    show (NotFunction message func)    = message ++ ": " ++ show func
    show (NumArgs expected found)      = "Expected " ++ show expected 
                                       ++ " args; found values " ++ unwordsList found
    show (TypeMismatch expected found) = "Invalid type: expected " ++ expected
                                       ++ ", found " ++ show found
    show (Parser parseErr)             = "Parse error at " ++ show parseErr

type ThrowsError = Either SchemeError

trapError action = catchError action (return . show)

type Env = IORef [(String, IORef SchemeVal)]

nullEnv :: IO Env
nullEnv = newIORef []

type IOThrowsError = ExceptT SchemeError IO

liftThrows :: ThrowsError a -> IOThrowsError a
liftThrows (Left err) = throwError err
liftThrows (Right val) = return val

isDefined :: Env -> String -> IO Bool
isDefined envRef var = readIORef envRef >>= return . maybe False (const True) . lookup var

getVar :: Env -> String -> IOThrowsError SchemeVal
getVar envRef var = do
    env <- liftIO $ readIORef envRef
    maybe (throwError $ UnboundVar "Getting an undefined variable" var)
        (liftIO . readIORef)
        (lookup var env)

setVar :: Env -> String -> SchemeVal -> IOThrowsError SchemeVal
setVar envRef var value = do
    env <- liftIO $ readIORef envRef
    maybe (throwError $ UnboundVar "Setting an undefined variable" var)
        (liftIO . (flip writeIORef value))
        (lookup var env)
    return value

defineVar :: Env -> String -> SchemeVal -> IOThrowsError SchemeVal
-- defineVar envRef var value = do
--      alreadyDefined <- liftIO $ isDefined envRef var
--      if alreadyDefined
--         then envRef var value >> return value
--         else liftIO $ do
--             valueRef <- newIORef value
--             env <- readIORef envRef
--             writeIORef envRef ((var, valueRef) : env)
--             return value
defineVar envRef var value = do
    liftIO $ do
        valueRef <- newIORef value
        env <- readIORef envRef
        writeIORef envRef ((var, valueRef) : env)
        return value

bindVars :: Env -> [(String, SchemeVal)] -> IO Env
bindVars envRef bindings = readIORef envRef >>= extendEnv bindings >>= newIORef
     where extendEnv bindings env = liftM (++ env) (mapM addBinding bindings)
           addBinding (var, value) = do ref <- newIORef value
                                        return (var, ref)
