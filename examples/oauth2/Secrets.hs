{-# LANGUAGE TemplateHaskell #-}

module Secrets (loadSecrets) where

import Language.Haskell.TH
import System.IO.Unsafe

loadSecrets :: Q [Dec]
loadSecrets = do
    let (id:secret:_) = lines $ unsafePerformIO (readFile "examples/oauth2/Secrets")
    let idExp = LitE (StringL id)
    let secretExp = LitE (StringL secret)
    return 
        [ FunD (mkName "clientId") [Clause [] (NormalB idExp) []]
        , FunD (mkName "clientSecret") [Clause [] (NormalB secretExp) []]
        ]

