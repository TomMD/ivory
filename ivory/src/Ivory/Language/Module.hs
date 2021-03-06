{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module Ivory.Language.Module where

import Ivory.Language.Area (IvoryArea)
import Ivory.Language.MemArea (MemArea(..),ConstMemArea(..))
import Ivory.Language.Proc (Def(..))
import Ivory.Language.Proxy (Proxy(..), ASymbol)
import Ivory.Language.String (IvoryString(..))
import Ivory.Language.Struct (IvoryStruct(..),StructDef(..),StructName)
import qualified Ivory.Language.Syntax as I

import Control.Monad (forM_)
import Control.Applicative
import Data.Monoid
import MonadLib (ReaderT,WriterT,ReaderM,WriterM,Id,runM,put,ask,local)
import MonadLib.Derive (Iso (..),derive_ask,derive_put)
import qualified Data.Set as Set


-- Modules ---------------------------------------------------------------------

data Visible = Public | Private deriving (Show)

newtype ModuleM a = Module
  { unModule :: ReaderT Visible (WriterT I.Module Id) a
  } deriving (Functor,Monad,Applicative)

instance ReaderM ModuleM Visible where
  ask = derive_ask (Iso Module unModule)

instance WriterM ModuleM I.Module where
  put = derive_put (Iso Module unModule)

type ModuleDef = ModuleM ()

instance Monoid (ModuleM ()) where
  mempty = return ()
  mappend a b = a >> b

-- | Add an element to the public/private list, depending on visibility
visAcc :: Visible -> a -> I.Visible a
visAcc vis e = case vis of
                       Public  -> I.Visible { I.public  = [e], I.private = [] }
                       Private -> I.Visible { I.public = [], I.private = [e] }

-- | Include a defintion in the module.
incl :: Def a -> ModuleDef
incl (DefProc p)    = do
  visibility <- ask
  put (mempty { I.modProcs   = visAcc visibility p })
incl (DefExtern e)  = put (mempty { I.modExterns = [e] })
incl (DefImport i)  = put (mempty { I.modImports = [i] })

-- | Add a dependency on an external header.
inclHeader :: String -> ModuleDef
inclHeader inc = put (mempty { I.modHeaders = Set.singleton inc })

-- | Add a dependency on another module.
depend :: I.Module -> ModuleDef
depend m =
  put (mempty { I.modDepends = Set.singleton (I.modName m) })

-- | Include the definition of a structure in the module.
defStruct :: forall sym. (IvoryStruct sym, ASymbol sym) =>
  Proxy sym -> ModuleDef
defStruct _ = do
  visibility <- ask
  put (mempty { I.modStructs = visAcc visibility (getStructDef def) })
  where
  def :: StructDef sym
  def  = structDef

-- | Include the definition of a string type's structure.
defStringType :: forall str. (IvoryString str) => Proxy str -> ModuleDef
defStringType _ = defStruct (Proxy :: Proxy (StructName str))

-- | Include the definition of a memory area.
defMemArea :: IvoryArea area => MemArea area -> ModuleDef
defMemArea m = case m of
  MemImport ia -> put (mempty { I.modAreaImports = [ia] })
  MemArea a as -> do
    visibility <- ask
    put (mempty { I.modAreas = visAcc visibility a })
    forM_ as $ \aux -> do
      put (mempty { I.modAreas = visAcc Private aux })

-- | Include the definition of a constant memory area.
defConstMemArea :: IvoryArea area => ConstMemArea area -> ModuleDef
defConstMemArea (ConstMemArea m) = defMemArea m

-- | Package the module up. Default visibility is public.
package :: String -> ModuleDef -> I.Module
package name build = (snd (runM (unModule build) Public)) { I.modName = name }

-- | Start a block of definitions that should not be put in the header.
private :: ModuleDef -> ModuleDef
private build = Module $ local Private (unModule build)

-- | Start a block of definitions should be put in the header. This is the
-- default, and this function is just included to complement 'private'.
public :: ModuleDef -> ModuleDef
public build = Module $ local Public (unModule build)

-- Accessors -------------------------------------------------------------------

moduleName :: I.Module -> String
moduleName  = I.modName
