-- | Binary serialization of core block types.

module Pos.Binary.Core.Blockchain
       (
       ) where

import           Universum

import           Pos.Binary.Class (Bi (..), encodeListLen, enforceSize)
import           Pos.Binary.Core.Common ()
import qualified Pos.Core.Block.Blockchain as T
import           Pos.Crypto.Configuration (HasCryptoConfiguration, getProtocolMagic, protocolMagic)
import           Pos.Util.Util (cborError, toCborError)

instance ( Typeable b
         , Bi (T.BHeaderHash b)
         , Bi (T.BodyProof b)
         , Bi (T.ConsensusData b)
         , Bi (T.ExtraHeaderData b)
         , T.BlockchainHelpers b
         , HasCryptoConfiguration
         ) =>
         Bi (T.GenericBlockHeader b) where
    encode bh =  encodeListLen 5
              <> encode (getProtocolMagic protocolMagic)
              <> encode (T._gbhPrevBlock bh)
              <> encode (T._gbhBodyProof bh)
              <> encode (T._gbhConsensus bh)
              <> encode (T._gbhExtra bh)
    decode = do
        enforceSize "GenericBlockHeader b" 5
        blockMagic <- decode
        -- TODO include ProtocolMagic in the definition of GenericBlockHeader,
        -- and decode it, eliminating this failure case. Protocol magic checks
        -- must not happen in decoding.
        when (blockMagic /= getProtocolMagic protocolMagic) $ cborError
            "GenericBlockHeader failed with wrong magic: " <> show blockMagic
        _gbhPrevBlock <- ({-# SCC "decode_header_prev" #-} decode)
        _gbhBodyProof <- ({-# SCC "decode_header_body_proof" #-} decode)
        _gbhConsensus <- ({-# SCC "decode_header_consensus" #-} decode)
        _gbhExtra     <- ({-# SCC "decode_header_extra" #-} decode)
        toCborError $ T.recreateGenericHeader _gbhPrevBlock _gbhBodyProof _gbhConsensus _gbhExtra

instance ( Typeable b
         , Bi (T.BHeaderHash b)
         , Bi (T.BodyProof b)
         , Bi (T.ConsensusData b)
         , Bi (T.ExtraHeaderData b)
         , Bi (T.Body b)
         , Bi (T.ExtraBodyData b)
         , T.BlockchainHelpers b
         , HasCryptoConfiguration
         ) =>
         Bi (T.GenericBlock b) where
    encode gb =  encodeListLen 3
              <> encode (T._gbHeader gb)
              <> encode (T._gbBody gb)
              <> encode (T._gbExtra gb)
    decode = do
        enforceSize "GenericBlock" 3
        _gbHeader <- ({-# SCC "decode_block_header" #-} decode)
        _gbBody   <- ({-# SCC "decode_block_body" #-} decode)
        _gbExtra  <- ({-# SCC "decode_block_extra" #-} decode)
        toCborError $ T.recreateGenericBlock _gbHeader _gbBody _gbExtra
