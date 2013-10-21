{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module Ivory.Compile.AADL.Monad where

import MonadLib
import Data.Monoid

import Ivory.Compile.AADL.AST
import Ivory.Compile.AADL.Identifier

import qualified Ivory.Language.Syntax as I

newtype CompileM a = Compile
  { unCompile :: StateT Document (ReaderT (I.Module,[I.Module]) Id) a }
  deriving (Functor, Monad)

type Compile = CompileM ()

-- Using snoc to write to lists, reverse at end of run.
runCompile :: [I.Module] -> I.Module -> Compile -> Document
runCompile allms m (Compile c) = Document
  { doc_name        = identifier (I.modName m)
  , doc_imports     = reverse (doc_imports d)
  , doc_definitions = reverse (doc_definitions d)
  }
  where
  modulectx = (m, allms)
  d :: Document
  d = snd (runId (runReaderT modulectx (runStateT mempty c)))

writeTypeDefinition :: DTypeDef -> Compile
writeTypeDefinition dtdef = Compile $ do
  d <- get
  when (td `notElem` (doc_definitions d)) $
    set d { doc_definitions = td:(doc_definitions d) }
  where td = TypeDefinition dtdef

writeThreadDefinition :: ThreadDef -> Compile
writeThreadDefinition tdef = Compile $ do
  d <- get
  set d { doc_definitions = td:(doc_definitions d) }
  where td = ThreadDefinition tdef

writeProcessDefinition :: ProcessDef -> Compile
writeProcessDefinition pdef = Compile $ do
  d <- get
  set d { doc_definitions = pd:(doc_definitions d) }
  where pd = ProcessDefinition pdef

writeImport :: String -> Compile
writeImport i = Compile $ do
  d <- get
  when (i `notElem` (doc_imports d)) $ 
    set d { doc_imports = i:(doc_imports d) }

qualTypeName :: String -> String -> CompileM TypeName
qualTypeName q n = do
  writeImport q
  return $ QualTypeName q n

getIModContext :: CompileM (I.Module,[I.Module])
getIModContext = Compile $ lift ask
