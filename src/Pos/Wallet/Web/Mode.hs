{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell     #-}
{-# LANGUAGE TypeFamilies        #-}
{-# LANGUAGE TypeOperators       #-}

module Pos.Wallet.Web.Mode
    ( WalletWebMode
    , WalletWebModeContextTag
    , WalletWebModeContext(..)
    ) where

import           Universum

import qualified Control.Monad.Reader          as Mtl
import           Mockable                      (Production)
import           System.Wlog                   (HasLoggerName (..), LoggerName)

import           Pos.Block.Core                (Block, BlockHeader)
import           Pos.Block.Types               (Undo)
import           Pos.Communication.PeerState   (WithPeerState (..), clearPeerStateDefault,
                                                getAllStatesDefault, getPeerStateDefault)
import           Pos.Core                      (IsHeader)
import           Pos.DB                        (MonadGState (..))
import           Pos.DB.Block                  (MonadBlockDBWrite (..), dbGetBlockDefault,
                                                dbGetBlockSscDefault, dbGetHeaderDefault,
                                                dbGetHeaderSscDefault, dbGetUndoDefault,
                                                dbGetUndoSscDefault, dbPutBlundDefault)
import           Pos.DB.Class                  (MonadBlockDBGeneric (..), MonadDB (..),
                                                MonadDBRead (..))
import           Pos.DB.DB                     (gsAdoptedBVDataDefault)
import           Pos.DB.Redirect               (dbDeleteDefault, dbGetDefault,
                                                dbIterSourceDefault, dbPutDefault,
                                                dbWriteBatchDefault)

import           Pos.Client.Txp.Balances       (MonadBalances (..), getBalanceDefault,
                                                getOwnUtxosDefault)
import           Pos.Client.Txp.History        (MonadTxHistory (..), getTxHistoryDefault,
                                                saveTxDefault)
import           Pos.Discovery                 (HasDiscoveryContextSum (..),
                                                MonadDiscovery (..), findPeersSum,
                                                getPeersSum)
import           Pos.ExecMode.Context          ((:::), HasLens (..), modeContext)
import           Pos.Reporting                 (HasReportingContext (..))
import           Pos.Slotting.Class            (MonadSlots (..))
import           Pos.Slotting.Impl.Sum         (currentTimeSlottingSum,
                                                getCurrentSlotBlockingSum,
                                                getCurrentSlotInaccurateSum,
                                                getCurrentSlotSum)
import           Pos.Slotting.MemState         (MonadSlotsData (..),
                                                getSlottingDataDefault,
                                                getSystemStartDefault,
                                                putSlottingDataDefault,
                                                waitPenultEpochEqualsDefault)
import           Pos.Ssc.Class.Types           (HasSscContext (..), SscBlock)
import           Pos.Util                      (Some (..))
import           Pos.Util.JsonLog              (jsonLogDefault)
import           Pos.Util.TimeWarp             (CanJsonLog (..))
import           Pos.Wallet.Redirect           (MonadBlockchainInfo (..),
                                                MonadUpdates (..),
                                                applyLastUpdateWebWallet,
                                                blockchainSlotDurationWebWallet,
                                                connectedPeersWebWallet,
                                                localChainDifficultyWebWallet,
                                                networkChainDifficultyWebWallet,
                                                waitForUpdateWebWallet)
import           Pos.Wallet.SscType            (WalletSscType)
import           Pos.Wallet.Web.BListener      (MonadBListener (..), onApplyTracking,
                                                onRollbackTracking)
import           Pos.Wallet.Web.Server.Sockets (ConnectionsVar)
import           Pos.Wallet.Web.State.State    (WalletState)
import           Pos.Wallet.Web.Tracking       (MonadWalletTracking (..),
                                                syncOnImportWebWallet,
                                                syncWSetsAtStartWebWallet,
                                                txMempoolToModifierWebWallet)
import           Pos.WorkMode                  (RealModeContext)

modeContext [d|
    data WalletWebModeContext = WalletWebModeContext
        !(WalletState    ::: WalletState)
        !(ConnectionsVar ::: ConnectionsVar)
        !(RealModeContext WalletSscType)
    |]

wwmcRealModeContext :: Lens' WalletWebModeContext (RealModeContext WalletSscType)
wwmcRealModeContext f (WalletWebModeContext x1 x2 rmc) =
    WalletWebModeContext x1 x2 <$> f rmc

instance HasSscContext WalletSscType WalletWebModeContext where
    sscContext = wwmcRealModeContext . sscContext

instance HasDiscoveryContextSum WalletWebModeContext where
    discoveryContextSum = wwmcRealModeContext . discoveryContextSum

instance HasReportingContext WalletWebModeContext  where
    reportingContext = wwmcRealModeContext . reportingContext

data WalletWebModeContextTag

instance HasLens WalletWebModeContextTag WalletWebModeContext WalletWebModeContext where
    lensOf = identity

type WalletWebMode = Mtl.ReaderT WalletWebModeContext Production

instance WithPeerState WalletWebMode where
    getPeerState = getPeerStateDefault
    clearPeerState = clearPeerStateDefault
    getAllStates = getAllStatesDefault

instance MonadSlotsData WalletWebMode where
    getSystemStart = getSystemStartDefault
    getSlottingData = getSlottingDataDefault
    waitPenultEpochEquals = waitPenultEpochEqualsDefault
    putSlottingData = putSlottingDataDefault

instance MonadSlots WalletWebMode where
    getCurrentSlot = getCurrentSlotSum
    getCurrentSlotBlocking = getCurrentSlotBlockingSum
    getCurrentSlotInaccurate = getCurrentSlotInaccurateSum
    currentTimeSlotting = currentTimeSlottingSum

instance MonadDiscovery WalletWebMode where
    getPeers = getPeersSum
    findPeers = findPeersSum

instance {-# OVERLAPPING #-} HasLoggerName WalletWebMode where
    getLoggerName = view (lensOf @LoggerName)
    modifyLoggerName f = local (lensOf @LoggerName %~ f)

instance {-# OVERLAPPING #-} CanJsonLog WalletWebMode where
    jsonLog = jsonLogDefault

instance MonadDBRead WalletWebMode where
    dbGet = dbGetDefault
    dbIterSource = dbIterSourceDefault

instance MonadDB WalletWebMode where
    dbPut = dbPutDefault
    dbWriteBatch = dbWriteBatchDefault
    dbDelete = dbDeleteDefault

instance MonadBlockDBWrite WalletSscType WalletWebMode where
    dbPutBlund = dbPutBlundDefault

instance MonadBlockDBGeneric (BlockHeader WalletSscType) (Block WalletSscType) Undo WalletWebMode
  where
    dbGetBlock  = dbGetBlockDefault @WalletSscType
    dbGetUndo   = dbGetUndoDefault @WalletSscType
    dbGetHeader = dbGetHeaderDefault @WalletSscType

instance MonadBlockDBGeneric (Some IsHeader) (SscBlock WalletSscType) () WalletWebMode
  where
    dbGetBlock  = dbGetBlockSscDefault @WalletSscType
    dbGetUndo   = dbGetUndoSscDefault @WalletSscType
    dbGetHeader = dbGetHeaderSscDefault @WalletSscType

instance MonadGState WalletWebMode where
    gsAdoptedBVData = gsAdoptedBVDataDefault

instance MonadBListener WalletWebMode where
    onApplyBlocks = onApplyTracking
    onRollbackBlocks = onRollbackTracking

instance MonadUpdates WalletWebMode where
    waitForUpdate = waitForUpdateWebWallet
    applyLastUpdate = applyLastUpdateWebWallet

instance MonadBlockchainInfo WalletWebMode where
    networkChainDifficulty = networkChainDifficultyWebWallet
    localChainDifficulty = localChainDifficultyWebWallet
    connectedPeers = connectedPeersWebWallet
    blockchainSlotDuration = blockchainSlotDurationWebWallet

instance MonadBalances WalletWebMode where
    getOwnUtxos = getOwnUtxosDefault
    getBalance = getBalanceDefault

instance MonadTxHistory WalletSscType WalletWebMode where
    getTxHistory = getTxHistoryDefault @WalletSscType
    saveTx = saveTxDefault

instance MonadWalletTracking WalletWebMode where
    syncWSetsAtStart = syncWSetsAtStartWebWallet
    syncOnImport = syncOnImportWebWallet
    txMempoolToModifier = txMempoolToModifierWebWallet
