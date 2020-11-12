import { Wallet, Contract } from 'ethers'
import { Web3Provider } from 'ethers/providers'
import { deployContract } from 'ethereum-waffle'

import { expandTo18Decimals } from './utilities'

import DXswapFactory from 'dxswap-core/build/DXswapFactory.json'
import IDXswapPair from 'dxswap-core/build/IDXswapPair.json'

import ERC20 from '../../build/ERC20.json'
import WETH9 from '../../build/WETH9.json'
import DXswapRouter from '../../build/DXswapRouter.json'
import RouterEventEmitter from '../../build/RouterEventEmitter.json'
import DXswapRelayer from '../../build/DXswapRelayer.json'
import OracleCreator from '../../build/OracleCreator.json'


const overrides = {
  gasLimit: 9999999
}

interface DXswapFixture {
  token0: Contract
  token1: Contract
  WETH: Contract
  WETHPartner: Contract
  dxswapFactory: Contract
  routerEventEmitter: Contract
  router: Contract
  pair: Contract
  WETHPair: Contract
  dxswapPair: Contract
  dxswapRouter: Contract
  uniFactory: Contract
  uniRouter: Contract
  uniPair: Contract
  oracleCreator: Contract
  dxRelayer: Contract
}

export async function dxswapFixture(provider: Web3Provider, [wallet]: Wallet[]): Promise<DXswapFixture> {
  // deploy tokens
  const tokenA = await deployContract(wallet, ERC20, [expandTo18Decimals(10000)])
  const tokenB = await deployContract(wallet, ERC20, [expandTo18Decimals(10000)])
  const WETH = await deployContract(wallet, WETH9)
  const WETHPartner = await deployContract(wallet, ERC20, [expandTo18Decimals(10000)])

  // deploy DXswapFactory
  const dxswapFactory = await deployContract(wallet, DXswapFactory, [wallet.address])

  // deploy router
  const router = await deployContract(wallet, DXswapRouter, [dxswapFactory.address, WETH.address], overrides)
  const dxswapRouter = await deployContract(wallet, DXswapRouter, [dxswapFactory.address, WETH.address], overrides)
  const uniRouter = await deployContract(wallet, DXswapRouter, [dxswapFactory.address, WETH.address], overrides)

  // event emitter for testing
  const routerEventEmitter = await deployContract(wallet, RouterEventEmitter, [])

  // initialize DXswapFactory
  await dxswapFactory.createPair(tokenA.address, tokenB.address)
  const pairAddress = await dxswapFactory.getPair(tokenA.address, tokenB.address)
  const pair = new Contract(pairAddress, JSON.stringify(IDXswapPair.abi), provider).connect(wallet)
  const dxswapPair = new Contract(pairAddress, JSON.stringify(IDXswapPair.abi), provider).connect(wallet)

  const token0Address = await pair.token0()
  const token0 = tokenA.address === token0Address ? tokenA : tokenB
  const token1 = tokenA.address === token0Address ? tokenB : tokenA

  await dxswapFactory.createPair(WETH.address, WETHPartner.address)
  const WETHPairAddress = await dxswapFactory.getPair(WETH.address, WETHPartner.address)
  const WETHPair = new Contract(WETHPairAddress, JSON.stringify(IDXswapPair.abi), provider).connect(wallet)

  // deploy UniswapFactory
  const uniFactory = await deployContract(wallet, DXswapFactory, [wallet.address])

  // initialize DXswapFactory
  await uniFactory.createPair(tokenA.address, tokenB.address)
  const uniPairAddress = await uniFactory.getPair(tokenA.address, tokenB.address)
  const uniPair = new Contract(uniPairAddress, JSON.stringify(IDXswapPair.abi), provider).connect(wallet)

  // deploy oracleCreator
  const oracleCreator = await deployContract(wallet, OracleCreator)

  const dxRelayer = await deployContract(
    wallet,
    DXswapRelayer,
    [wallet.address, dxswapFactory.address, dxswapRouter.address, uniFactory.address, uniRouter.address, WETH.address, oracleCreator.address],
    overrides
  )

  return {
    token0,
    token1,
    WETH,
    WETHPartner,
    dxswapFactory,
    routerEventEmitter,
    router,
    pair,
    WETHPair,
    dxswapPair,
    dxswapRouter,
    uniFactory,
    uniRouter,
    uniPair,
    oracleCreator,
    dxRelayer
  }
}