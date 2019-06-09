module Main where
import Args
-- import Args

main :: IO ()
main = do
    args <- parseArgv
    print args
