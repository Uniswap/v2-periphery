import { Wallet, Contract } from 'ethers'
import { Web3Provider } from 'ethers/providers'
import { deployContract } from 'ethereum-waffle'

import { expandTo18Decimals } from './utilities'

import ERC20 from '../../build/ERC20.json'
import WETH9 from '../../build/WETH9.json'
import UniswapV1Exchange from '../../build/UniswapV1Exchange.json'
import UniswapV1Factory from '../../build/UniswapV1Factory.json'
import UniswapV2Factory from '../../build/UniswapV2Factory.json'
import UniswapV2Router from '../../build/UniswapV2Router.json'
import Migrator from '../../build/Migrator.json'
import IUniswapV2Exchange from '../../build/IUniswapV2Exchange.json'

const overrides = {
  gasLimit: 9999999
}

interface V2Fixture {
  token0: Contract
  token1: Contract
  WETH: Contract
  WETHPartner: Contract
  factoryV1: Contract
  factoryV2: Contract
  router: Contract
  migrator: Contract
  exchangeV1: Contract
  exchange: Contract
  WETHExchange: Contract
}

export async function v2Fixture(provider: Web3Provider, [wallet]: Wallet[]): Promise<V2Fixture> {
  // deploy tokens
  const tokenA = await deployContract(wallet, ERC20, [expandTo18Decimals(10000)])
  const tokenB = await deployContract(wallet, ERC20, [expandTo18Decimals(10000)])
  const WETH = await deployContract(wallet, WETH9)
  const WETHPartner = await deployContract(wallet, ERC20, [expandTo18Decimals(10000)])

  // deploy v1
  const factoryV1 = await deployContract(wallet, UniswapV1Factory, [])
  await factoryV1.initializeFactory((await deployContract(wallet, UniswapV1Exchange, [])).address)

  // deploy v1
  const factoryV2 = await deployContract(wallet, UniswapV2Factory, [wallet.address])

  // deploy router and migrator
  const router = await deployContract(wallet, UniswapV2Router, [WETH.address], overrides)
  const migrator = await deployContract(wallet, Migrator, [factoryV1.address], overrides)

  // initialize v1
  await factoryV1.createExchange(WETHPartner.address, overrides)
  const exchangeV1Address = await factoryV1.getExchange(WETHPartner.address)
  const exchangeV1 = new Contract(exchangeV1Address, JSON.stringify(UniswapV1Exchange.abi), provider).connect(wallet)

  // initialize V2
  await factoryV2.createExchange(tokenA.address, tokenB.address)
  const exchangeAddress = await factoryV2.getExchange(tokenA.address, tokenB.address)
  const exchange = new Contract(exchangeAddress, JSON.stringify(IUniswapV2Exchange.abi), provider).connect(wallet)

  await factoryV2.createExchange(WETH.address, WETHPartner.address)
  const WETHExchangeAddress = await factoryV2.getExchange(WETH.address, WETHPartner.address)
  const WETHExchange = new Contract(WETHExchangeAddress, JSON.stringify(IUniswapV2Exchange.abi), provider).connect(
    wallet
  )

  const token0Address = await exchange.token0()
  const token0 = tokenA.address === token0Address ? tokenA : tokenB
  const token1 = tokenA.address === token0Address ? tokenB : tokenA

  return {
    token0,
    token1,
    WETH,
    WETHPartner,
    factoryV1,
    factoryV2,
    router,
    migrator,
    exchangeV1,
    exchange,
    WETHExchange
  }
}
