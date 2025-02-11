module Syntactic where

import Codegen (Instruction (Instruction, argument1, operator), MetaData (MetaData), Operador (), meta)
import qualified Codegen as Gen
import Data.List (find)
import Data.Map (insert, member, (!))
import qualified Data.Map as Map
import Data.Maybe (fromJust, isJust, isNothing)
import qualified Data.Maybe
import Lexer (LexerResult, NumberType (Float, Integer), RowColumn (RowColumn), Token (Token, rowColumn, tag, value), TokenType (EOF, Identifier, KeyWord, Number, Symbol))
import Semantic (IdentifierType (ProgramName, Variable), ProgramType, SemanticData (SemanticData, currentType, genCode, symbolTable), getIdentifierType)
import qualified Semantic as Ge
import qualified Semantic as Gen
import qualified Semantic as Sem
import Utils (findAndReplace, head', last', tail1)

data AnalyzerError = FoundError String RowColumn | ExpectedAnyToken deriving (Show)

data AnalyzerResult = Success [Token] SemanticData | Error AnalyzerError deriving (Show)

addVariable :: [Token] -> SemanticData -> AnalyzerResult
addVariable tks@(x@Token {tag = Identifier} : _) sd =
  if member v st
    then Error $ FoundError ("Variavel \"" ++ v ++ "\" ja foi declarada") rc
    else case numberType of
      Just a -> case a of
        ProgramName ->
          Success tks $ sd {symbolTable = insert v a st}
        Variable _ (Sem.Number number) ->
          Success tks $ Sem.appendCodeGen Gen.variable sd {symbolTable = insert v a st}
        _ -> Error $ FoundError (v ++ " nao e um tipo valido") rc
      Nothing -> Error $ FoundError (v ++ " nao e um tipo valido") rc
  where
    SemanticData {symbolTable = st} = sd
    Token {value = v, tag = t, rowColumn = rc} = x
    numberType = getIdentifierType x sd
addVariable (Token {rowColumn = rc, value = v} : _) sd = Error $ FoundError ("Esperado identificador real ou inteiro, encontrado: " ++ v) rc
addVariable tks sd = Error ExpectedAnyToken

addInitGen :: [Token] -> SemanticData -> AnalyzerResult
addInitGen tks sd = Success tks $ Sem.addInpp sd

addStopCodeGen :: [Token] -> SemanticData -> AnalyzerResult
addStopCodeGen tks sd = Success tks $ Sem.addStop sd

addMetaLastCodeGen :: String -> [Token] -> SemanticData -> AnalyzerResult
addMetaLastCodeGen meta tks sd = Success tks $ Sem.addMeta meta sd

addIncrementalMetaLastCodeGen :: String -> [Token] -> SemanticData -> AnalyzerResult
addIncrementalMetaLastCodeGen meta tks sd = Success tks $ Sem.createNewTag meta sd

addCodegenFunction :: String -> [Token] -> SemanticData -> AnalyzerResult
addCodegenFunction fuctionName tks@(x : xs) sd =
  -- TODO Ajusta busca do indice da variavel
  case variable of
    Variable index _ -> Success tks $ Gen.appendCodesGen (Gen.functionCall fuctionName index) sd
    _ -> Error $ FoundError "Esperado uma variavel" $ rowColumn x
  where
    variableName = value x
    SemanticData {symbolTable = st} = sd
    variable = st ! variableName
addCodegenFunction _ [] sd = Success [] sd

addVariableToInstructions :: [Token] -> SemanticData -> AnalyzerResult
addVariableToInstructions [] sd = Error ExpectedAnyToken
addVariableToInstructions tks@(x : xs) sd =
  case (Gen.isMathOperator lastIns, meta lastIns) of
    (_, Just (MetaData "endExpression")) -> Success tks $ Gen.appendCodeGen newIns sd
    (True, _) -> Success tks $ sd {genCode = newGenCode}
    _ -> Success tks $ Gen.appendCodeGen newIns sd
  where
    parans = value x
    newIns = Gen.loadVariable $ Sem.findVariableIndex parans sd
    instructions = genCode sd
    lastIns = last instructions
    newGenCode = init instructions ++ [newIns] ++ [lastIns]

addValueToInstructions :: [Token] -> SemanticData -> AnalyzerResult
addValueToInstructions [] sd = Error ExpectedAnyToken
addValueToInstructions tks@(x : xs) sd =
  case (Gen.isMathOperator lastIns, meta lastIns) of
    (_, Just (MetaData "endExpression")) -> Success tks $ Gen.appendCodeGen newIns sd
    (True, _) -> Success tks $ sd {genCode = newGenCode}
    _ -> Success tks $ Gen.appendCodeGen newIns sd
  where
    newIns = Gen.loadValue (read parans :: Int)
    parans = value x
    instructions = genCode sd
    lastIns = last instructions
    newGenCode = init instructions ++ [newIns] ++ [lastIns]

addMathToInstructions :: String -> [Token] -> SemanticData -> AnalyzerResult
addMathToInstructions parans [] sd = Error ExpectedAnyToken
addMathToInstructions parans tks@(x : xs) sd =
  Success tks $ Sem.appendCodeGen mathIns sd
  where
    mathIns = Gen.mathOperator $ value x

addAssignment :: String -> [Token] -> SemanticData -> AnalyzerResult
addAssignment variable tks sd =
  Success tks $ Gen.appendCodeGen (Gen.assignmentVariable $ Sem.findVariableIndex variable sd) sd

addJfCodeGen :: [Token] -> SemanticData -> AnalyzerResult
addJfCodeGen = Success

addInstructionMeta :: String -> [Token] -> SemanticData -> AnalyzerResult
addInstructionMeta tag tks sd =
  Success tks sd
  where
    Token {value = value} = head tks

addCurrentType :: ProgramType -> [Token] -> SemanticData -> AnalyzerResult
addCurrentType pt tks sd = Success tks $ sd {currentType = Just pt}

addCompareCodeGen :: String -> [Token] -> SemanticData -> AnalyzerResult
addCompareCodeGen comparer tks sd = Success tks $ Gen.appendCodeGen (Gen.compareOperator comparer) sd

addDsvfCodeGen :: [Token] -> SemanticData -> AnalyzerResult
addDsvfCodeGen tks sd = Success tks $ Gen.appendCodeGen Gen.dsvfOperator sd

fixLastDsvfArgument :: [Token] -> SemanticData -> AnalyzerResult
fixLastDsvfArgument tks sd = Success tks sd {genCode = newList}
  where
    ins = genCode sd
    compareFuncion x = case x of
      Instruction Gen.DSVF _ _ -> True
      _ -> False
    newList = findAndReplace compareFuncion Gen.dsvfOperator {argument1 = 1 + length ins} ins

fixLastDsviArgument :: [Token] -> SemanticData -> AnalyzerResult
fixLastDsviArgument tks sd = Success tks sd {genCode = newList}
  where
    ins = genCode sd
    compareFuncion x = case x of
      Instruction Gen.DSVI _ _ -> True
      _ -> False
    newList = findAndReplace compareFuncion (Gen.dsviOperator $ 1 + length ins) ins

incrementLastDsvfArgument :: [Token] -> SemanticData -> AnalyzerResult
incrementLastDsvfArgument tks sd = Success tks sd {genCode = newList}
  where
    ins = genCode sd
    compareFuncion x = case x of
      Instruction Gen.DSVF _ _ -> True
      _ -> False
    newOp = fromJust $ find compareFuncion ins
    newList = findAndReplace compareFuncion newOp {argument1 = 1 + argument1 newOp} ins

addDsviCodeGen :: Int -> [Token] -> SemanticData -> AnalyzerResult
addDsviCodeGen index tks sd = Success tks $ Gen.appendCodeGen (Gen.dsviOperator index) sd

removeType :: [Token] -> SemanticData -> AnalyzerResult
removeType tks sd = Success tks $ sd {currentType = Nothing}

verifyIfIdentifierExist :: [Token] -> SemanticData -> AnalyzerResult
verifyIfIdentifierExist tks@(x : xs) sd = case result of
  Just a -> case a of
    ProgramName -> Error $ FoundError "Nome do programa nao pode ser usado" rc
    _ -> Success tks sd
  Nothing -> Error $ FoundError ("Variavel \"" ++ v ++ "\" nao declarada") rc
  where
    SemanticData {symbolTable = st} = sd
    Token {value = v, rowColumn = rc} = x
    result = Map.lookup v st
verifyIfIdentifierExist tks sd = Success tks sd

setCurrentTypeIfNotExist :: [Token] -> SemanticData -> AnalyzerResult
setCurrentTypeIfNotExist tks@(x : xs) sd =
  if isNothing currentType
    then case tag x of
      Identifier -> case variableType of
        Just a -> case a of
          Sem.Variable _ numberType -> Success tks $ sd {currentType = Just numberType}
          _ -> Error $ FoundError "Nao foi encontrado tipo" rc
        _ -> Error $ FoundError ("Variavel " ++ v ++ " nao encontrada") rc
      Number numberType -> Success tks $ sd {currentType = Just $ Sem.Number numberType}
      _ -> Error $ FoundError "Nao foi encontrado tipo" rc
    else Success tks sd
  where
    v = value x
    rc = rowColumn x
    SemanticData {symbolTable = symbolTable, currentType = currentType} = sd
    variableType = Map.lookup v symbolTable
setCurrentTypeIfNotExist tks sd = Success tks sd

verifyCurrentType :: [Token] -> SemanticData -> AnalyzerResult
verifyCurrentType (x : xs) sd =
  case (tokenType, currentType) of
    (Just a, Just b) -> case a of
      Variable _ pt ->
        if pt == b
          then Success (x : xs) sd
          else Error $ FoundError ("Foi encontrado: " ++ show pt ++ " esperado: " ++ show b) rc
      _ -> Error $ FoundError "Nao foi encontrado tipagem para essa expressao" rc
    (_, _) -> Error $ FoundError "Nao foi encontrado tipagem para essa expressao" rc
  where
    SemanticData {currentType = currentType, symbolTable = symbolTable} = sd
    rc = rowColumn x
    tokenType = case tag x of
      Identifier -> Map.lookup (value x) symbolTable
      -- Exibir indice
      Number numberType -> Just $ Sem.Variable 0 $ Sem.Number numberType
      _ -> Nothing
verifyCurrentType _ _ = Error ExpectedAnyToken

setCurrentTypeForVariableType :: [Token] -> SemanticData -> AnalyzerResult
setCurrentTypeForVariableType tks@(x : xs) sd =
  case result of
    Just a -> case a of
      ProgramName -> Error $ FoundError "Nome do programa nao pode ser usado" rc
      Variable _ (Sem.Number nt) -> Success tks $ sd {currentType = Just $ Sem.Number nt}
      _ -> Error $ FoundError "Erro inesperado" rc
    Nothing -> Error $ FoundError ("Variavel \"" ++ v ++ "\" nao declarada") rc
  where
    SemanticData {symbolTable = st} = sd
    Token {tag = Identifier, value = v, rowColumn = rc} = x
    result = Map.lookup v st
setCurrentTypeForVariableType tks sd = Success tks sd

skipToken :: [Token] -> SemanticData -> AnalyzerResult
skipToken (x : xs) sd = Success xs sd
skipToken tks sd = Success tks sd

assertValue esperado obtido = "Esperado: " ++ esperado ++ " obtido: " ++ obtido

tokenTypeToError :: TokenType -> String
tokenTypeToError tokenType = case tokenType of
  Symbol -> "Esperado um simbolo"
  KeyWord -> "Esperado uma palavra reservada"
  Identifier -> "Esperado um identificador"
  EOF -> "Esperado final do arquivo"
  Number _ -> "Esperado um numero"

transformValidade :: ([Token] -> (Bool, String)) -> [Token] -> SemanticData -> AnalyzerResult
transformValidade f token sd =
  if isValid
    then Success (tail token) sd
    else Error $ FoundError error rc
  where
    (isValid, error) = f token
    Token {rowColumn = rc} = head token

validadeValue :: String -> [Token] -> SemanticData -> AnalyzerResult
validadeValue value = transformValidade (\(Token {value = tValue} : xs) -> (value == tValue, assertValue value tValue))

validadeTag :: TokenType -> [Token] -> SemanticData -> AnalyzerResult
validadeTag tag = transformValidade (\(Token {tag = tTag, value = v} : xs) -> (tag == tTag, tokenTypeToError tag ++ " encontrado: " ++ v))

validadeSyntactic :: [[Token] -> SemanticData -> AnalyzerResult] -> [Token] -> SemanticData -> AnalyzerResult
validadeSyntactic [] tokens sd = Success tokens sd
validadeSyntactic (f : fs) tokens sd
  | Success tokens sd <- result = validadeSyntactic fs tokens sd
  | Error {} <- result = result
  where
    result = f tokens sd

addSemanticValidation :: (AnalyzerResult -> AnalyzerResult) -> [Token] -> SemanticData -> AnalyzerResult
addSemanticValidation f tks sd = f $ Success tks sd

validadeAfter :: ([Token] -> SemanticData -> AnalyzerResult) -> ([Token] -> SemanticData -> AnalyzerResult) -> [Token] -> SemanticData -> AnalyzerResult
validadeAfter f1 f2 tks sd =
  case result1 of
    Success ntks nsd ->
      case result2 of
        Success _ nsd2 -> Success ntks nsd2
        Error _ -> result2
      where
        result2 = f2 tks nsd
    Error _ -> result1
  where
    result1 = f1 tks sd

executeMany :: [[Token] -> SemanticData -> AnalyzerResult] -> [Token] -> SemanticData -> AnalyzerResult
executeMany (f : fs) tks sd =
  case result of
    Success _ nsd -> executeMany fs tks nsd
    _ -> result
  where
    result = f tks sd
executeMany [] tks sd = Success tks sd

semanticPipeline :: [Token] -> SemanticData -> [AnalyzerResult -> AnalyzerResult] -> Maybe AnalyzerResult
semanticPipeline tks sd = head' . tail1 . dropWhile (not . compareError) . scanl (\acc fun -> fun acc) (Success tks sd)
  where
    compareError as
      | Error _ <- as = False
      | otherwise = True

validadeSemantic :: ([Token] -> SemanticData -> AnalyzerResult) -> [AnalyzerResult -> AnalyzerResult] -> [Token] -> SemanticData -> AnalyzerResult
validadeSemantic f fs tks sd =
  case result of
    (Success tokens semantic) -> case validation of
      Just (Success _ resultSd) -> Success tokens resultSd
      Just (Error a) -> Error a
      _ -> result
    (Error _) -> result
  where
    result = f tks sd
    (Success _ rSd) = result
    validation = semanticPipeline tks rSd fs

tipoVar :: [Token] -> SemanticData -> AnalyzerResult
tipoVar [] _ = Error ExpectedAnyToken
tipoVar (x : xs) sd
  | v == "real" = Success xs $ sd {currentType = Just $ Sem.Number Float}
  | v == "integer" = Success xs $ sd {currentType = Just $ Sem.Number Integer}
  | otherwise = Error $ FoundError ("Esperado identificador real ou inteiro, encontrado: " ++ v) rc
  where
    Token {value = v, rowColumn = rc} = x

pFalsa :: [Token] -> SemanticData -> AnalyzerResult
pFalsa [] _ = Error ExpectedAnyToken
pFalsa (x : xs) sd
  | v == "else" =
    validadeSyntactic
      [ addDsviCodeGen 0,
        comandos,
        fixLastDsviArgument,
        incrementLastDsvfArgument
      ]
      xs
      sd
  | otherwise = Success (x : xs) sd
  where
    Token {value = v, rowColumn = rc, tag = t} = x

maisFatores :: [Token] -> SemanticData -> AnalyzerResult
maisFatores [] _ = Error ExpectedAnyToken
maisFatores (x : xs) sd
  | v == "*" || v == "/" =
    validadeSyntactic
      [ addMathToInstructions v,
        skipToken,
        fator,
        maisFatores
      ]
      (x : xs)
      sd
  | otherwise = Success (x : xs) sd
  where
    Token {value = v, rowColumn = rc, tag = t} = x

outrosTermos :: [Token] -> SemanticData -> AnalyzerResult
outrosTermos [] _ = Error ExpectedAnyToken
outrosTermos (x : xs) sd
  | v == "+" || v == "-" =
    validadeSyntactic
      [ addMathToInstructions v,
        skipToken,
        termo,
        outrosTermos
      ]
      (x : xs)
      sd
  | otherwise = Success (x : xs) sd
  where
    Token {value = v, rowColumn = rc, tag = t} = x

fator :: [Token] -> SemanticData -> AnalyzerResult
fator [] _ = Error ExpectedAnyToken
fator (x : xs) sd
  | t == Identifier =
    validadeSyntactic
      [ verifyIfIdentifierExist,
        setCurrentTypeIfNotExist,
        verifyCurrentType,
        addVariableToInstructions,
        addIncrementalMetaLastCodeGen "fator",
        skipToken
      ]
      (x : xs)
      sd
  | t == Number Integer =
    validadeSyntactic
      [ setCurrentTypeIfNotExist,
        verifyCurrentType,
        addValueToInstructions,
        skipToken
      ]
      (x : xs)
      sd
  | t == Number Float =
    validadeSyntactic
      [ setCurrentTypeIfNotExist,
        verifyCurrentType,
        addValueToInstructions,
        skipToken
      ]
      (x : xs)
      sd
  | v == "(" =
    validadeSyntactic
      [ expressao,
        validadeValue ")"
      ]
      xs
      sd
  | otherwise = Error $ FoundError (show x) rc
  where
    Token {value = v, rowColumn = rc, tag = t} = x

opUn :: [Token] -> SemanticData -> AnalyzerResult
opUn [] _ = Error ExpectedAnyToken
opUn (x : xs) sd
  | v == "-" = Success xs sd
  | otherwise = Success (x : xs) sd
  where
    Token {value = v, rowColumn = rc} = x

termo :: [Token] -> SemanticData -> AnalyzerResult
termo =
  validadeSyntactic
    [ opUn,
      fator,
      maisFatores
    ]

expressao :: [Token] -> SemanticData -> AnalyzerResult
expressao =
  validadeSyntactic
    [ termo,
      outrosTermos,
      addMetaLastCodeGen "endExpression"
    ]

relacao :: [Token] -> SemanticData -> AnalyzerResult
relacao [] _ = Error ExpectedAnyToken
relacao tks@(x : xs) sd =
  if v `elem` ["<", ">", "=", "<>", ">=", "<="]
    then Success tks sd
    else Error $ FoundError "Esperado simbolo de comparação" rc
  where
    Token {value = v, rowColumn = rc} = x

condicao :: [Token] -> SemanticData -> AnalyzerResult
condicao tks sd =
  case firstExpressionResult of
    Success rtks rsd ->
      let relacaoValue = value $ head rtks
       in validadeSyntactic
            [ relacao,
              skipToken,
              expressao,
              addCompareCodeGen relacaoValue,
              addDsvfCodeGen
            ]
            rtks
            rsd
    _ -> firstExpressionResult
  where
    firstExpressionResult = expressao tks sd

comando :: [Token] -> SemanticData -> AnalyzerResult
comando [] _ = Error ExpectedAnyToken
comando (x : xs) sd
  | v == "read" || v == "write" =
    validadeSyntactic
      [ validadeValue "(",
        executeMany [validadeTag Identifier, verifyIfIdentifierExist, addCodegenFunction v],
        skipToken,
        validadeValue ")"
      ]
      xs
      sd
  | t == Identifier =
    validadeSyntactic
      [ setCurrentTypeForVariableType,
        skipToken,
        validadeValue ":=",
        expressao,
        addAssignment v
      ]
      (x : xs)
      sd
  | v == "if" =
    validadeSyntactic
      [ condicao,
        validadeValue "then",
        comandos,
        fixLastDsvfArgument,
        pFalsa,
        validadeValue "$"
      ]
      xs
      sd
  | v == "while" =
    let whileBegin = 1 + length (genCode sd)
     in validadeSyntactic
          [ condicao,
            validadeValue "do",
            comandos,
            fixLastDsvfArgument,
            addDsviCodeGen whileBegin,
            validadeValue "$"
          ]
          xs
          sd
  | otherwise = Error $ FoundError ("Comando invalido: " ++ v) rc
  where
    Token {value = v, rowColumn = rc, tag = t} = x

maisComandos :: [Token] -> SemanticData -> AnalyzerResult
maisComandos [] _ = Error ExpectedAnyToken
maisComandos (x : xs) sd
  | v == ";" = validadeSyntactic [removeType, comandos] xs sd
  | otherwise = Success (x : xs) sd
  where
    Token {value = v, rowColumn = rc} = x

comandos :: [Token] -> SemanticData -> AnalyzerResult
comandos =
  validadeSyntactic
    [ comando,
      maisComandos
    ]

maisVar :: [Token] -> SemanticData -> AnalyzerResult
maisVar [] _ = Error ExpectedAnyToken
maisVar (x : xs) sd
  | v == "," = variaveis xs sd
  | otherwise = Success (x : xs) sd
  where
    Token {value = v, rowColumn = rc} = x

variaveis :: [Token] -> SemanticData -> AnalyzerResult
variaveis =
  validadeSyntactic
    [ executeMany [validadeTag Identifier, addVariable],
      skipToken,
      maisVar
    ]

dcV :: [Token] -> SemanticData -> AnalyzerResult
dcV =
  validadeSyntactic
    [ tipoVar,
      validadeValue ":",
      variaveis
    ]

maisDc :: [Token] -> SemanticData -> AnalyzerResult
maisDc [] _ = Error ExpectedAnyToken
maisDc (x : xs) sd
  | v == ";" = dc xs sd
  | otherwise = Success (x : xs) sd
  where
    Token {value = v, rowColumn = rc} = x

dc :: [Token] -> SemanticData -> AnalyzerResult
dc [] _ = Error ExpectedAnyToken
dc (x : xs) sd
  | v == "real" || v == "integer" =
    validadeSyntactic
      [ dcV,
        maisDc
      ]
      (x : xs)
      sd
  | otherwise = Success (x : xs) sd
  where
    Token {value = v, rowColumn = rc} = x

corpo :: [Token] -> SemanticData -> AnalyzerResult
corpo =
  validadeSyntactic
    [ dc,
      removeType,
      validadeValue "begin",
      comandos,
      validadeValue "end"
    ]

programa :: [Token] -> SemanticData -> AnalyzerResult
programa =
  validadeSyntactic
    [ validadeValue "program",
      addInitGen,
      addVariable,
      validadeTag Identifier,
      corpo,
      validadeValue ".",
      addStopCodeGen,
      validadeTag EOF
    ]
