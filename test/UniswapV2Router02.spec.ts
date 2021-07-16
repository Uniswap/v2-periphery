import chai, { expect } from 'chai'
import { Contract } from 'ethers'
import { solidity, MockProvider, createFixtureLoader,deployContract } from 'ethereum-waffle'
import { BigNumber, constants as ethconst, Wallet } from 'ethers'
import { ethers, waffle } from 'hardhat'

import IUniswapV2Pair from '../buildV1/UniswapV2Pair.json'

import UniswapV2Factory from '../buildV1/UniswapV2Factory.json'
import ContangoPair from '../buildV1/ContangoPair.json'
import { expandTo18Decimals, getApprovalDigest, MINIMUM_LIQUIDITY ,getCreate2Address} from './shared/utilities'
import { utils as ethutil } from 'ethers'

const {  keccak256,  } = ethutil

import { ecsign } from 'ethereumjs-util'



const overrides = {
  gasLimit: 9999999
}
const BN = BigNumber;
describe('UniswapV2Router02', () => {

  const loadFixture = waffle.createFixtureLoader(waffle.provider.getWallets(), waffle.provider)
	async function v2Fixture([wallet, other]: Wallet[], provider: MockProvider) {
  
		const factoryV2 = await deployContract(wallet,UniswapV2Factory,[wallet.address])
		const tokenA = await (await ethers.getContractFactory('ERC20')).deploy(expandTo18Decimals(1000000))
		const tokenB = await (await ethers.getContractFactory('ERC20')).deploy(expandTo18Decimals(1000000))

		await factoryV2.createPair(tokenA.address, tokenB.address, 200000)

    const contangoPairFactory = new ethers.ContractFactory(ContangoPair.abi,ContangoPair.bytecode)
    const pairAddress = await factoryV2.getPair(tokenA.address, tokenB.address)
		const pair = await ethers.getContractAt(ContangoPair.abi,pairAddress)
		const token0Address = await pair.token0()
    const weth = await(await ethers.getContractFactory('WETH9')).deploy()
		const token0 = tokenA.address === token0Address ? tokenA : tokenB
		const token1 = tokenA.address === token0Address ? tokenB : tokenA
    const router02 = await(await ethers.getContractFactory('UniswapV2Router02')).deploy(factoryV2.address,weth.address)
		return { pair, token0, token1, wallet, other, factoryV2, provider,router02 }
	}

  let token0: Contract
  let token1: Contract
  let router: Contract
  let wallet:Wallet
  beforeEach(async function() {
    const fixture = await loadFixture(v2Fixture)
    token0 = fixture.token0
    token1 = fixture.token1
    router = fixture.router02
    wallet = fixture.wallet
  })

  it('quote', async () => {
    
    expect(await router.quote(BN.from(1), BN.from(100), BN.from(200))).to.eq(BN.from(2))
    expect(await router.quote(BN.from(2), BN.from(200), BN.from(100))).to.eq(BN.from(1))
    await expect(router.quote(BN.from(0), BN.from(100), BN.from(200))).to.be.revertedWith(
      'UniswapV2Library: INSUFFICIENT_AMOUNT'
    )
    await expect(router.quote(BN.from(1), BN.from(0), BN.from(200))).to.be.revertedWith(
      'UniswapV2Library: INSUFFICIENT_LIQUIDITY'
    )
    await expect(router.quote(BN.from(1), BN.from(100), BN.from(0))).to.be.revertedWith(
      'UniswapV2Library: INSUFFICIENT_LIQUIDITY'
    )
  })

  it('getAmountOut', async () => {
    
    expect(await router.getAmountOut(BN.from(2), BN.from(100), BN.from(100))).to.eq(BN.from(1))
    await expect(router.getAmountOut(BN.from(0), BN.from(100), BN.from(100))).to.be.revertedWith(
      'UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT'
    )
    await expect(router.getAmountOut(BN.from(2), BN.from(0), BN.from(100))).to.be.revertedWith(
      'UniswapV2Library: INSUFFICIENT_LIQUIDITY'
    )
    await expect(router.getAmountOut(BN.from(2), BN.from(100), BN.from(0))).to.be.revertedWith(
      'UniswapV2Library: INSUFFICIENT_LIQUIDITY'
    )
  })

  it('getAmountIn', async () => {
    
    expect(await router.getAmountIn(BN.from(1), BN.from(100), BN.from(100))).to.eq(BN.from(2))
    await expect(router.getAmountIn(BN.from(0), BN.from(100), BN.from(100))).to.be.revertedWith(
      'UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT'
    )
    await expect(router.getAmountIn(BN.from(1), BN.from(0), BN.from(100))).to.be.revertedWith(
      'UniswapV2Library: INSUFFICIENT_LIQUIDITY'
    )
    await expect(router.getAmountIn(BN.from(1), BN.from(100), BN.from(0))).to.be.revertedWith(
      'UniswapV2Library: INSUFFICIENT_LIQUIDITY'
    )
  })

  it('getAmountsOut', async () => {
    
    await token0.approve(router.address, ethers.constants.MaxUint256)
    await token1.approve(router.address, ethers.constants.MaxUint256)
    await router.addLiquidity(
      token0.address,
      token1.address,
      BN.from(10000),
      BN.from(10000),
      0,
      0,
      wallet.address,
      ethers.constants.MaxUint256,
      overrides
    )

    await expect(router.getAmountsOut(BN.from(2), [token0.address])).to.be.revertedWith(
      'UniswapV2Library: INVALID_PATH'
    )
    const path = [token0.address, token1.address]
    expect(await router.getAmountsOut(BN.from(2), path)).to.deep.eq([BN.from(2), BN.from(1)])
  })

  it('getAmountsIn', async () => {
    
    await token0.approve(router.address, ethers.constants.MaxUint256)
    await token1.approve(router.address, ethers.constants.MaxUint256)
    await router.addLiquidity(
      token0.address,
      token1.address,
      BN.from(10000),
      BN.from(10000),
      0,
      0,
      wallet.address,
      ethers.constants.MaxUint256,
      overrides
    )

    await expect(router.getAmountsIn(BN.from(1), [token0.address])).to.be.revertedWith(
      'UniswapV2Library: INVALID_PATH'
    )
    const path = [token0.address, token1.address]
    expect(await router.getAmountsIn(BN.from(1), path)).to.deep.eq([BN.from(2), BN.from(1)])
  })
})

describe('fee-on-transfer tokens', () => {
  const provider = ethers.getDefaultProvider();
 const loadFixture = waffle.createFixtureLoader(waffle.provider.getWallets(), waffle.provider)
 async function v2Fixture([wallet, other]: Wallet[], provider: MockProvider) {
  
  const factoryV2 = await deployContract(wallet,UniswapV2Factory,[wallet.address])
  const tokenA = await (await ethers.getContractFactory('ERC20')).deploy(expandTo18Decimals(1000000))
  const tokenB = await (await ethers.getContractFactory('ERC20')).deploy(expandTo18Decimals(1000000))

  await factoryV2.createPair(tokenA.address, tokenB.address, 200000)

  const contangoPairFactory = new ethers.ContractFactory(ContangoPair.abi,ContangoPair.bytecode)
  const pairAddress = await factoryV2.getPair(tokenA.address, tokenB.address)
  const pair = await ethers.getContractAt(ContangoPair.abi,pairAddress)
  const token0Address = await pair.token0()
  const WETH = await(await ethers.getContractFactory('WETH9')).deploy()
  const token0 = tokenA.address === token0Address ? tokenA : tokenB
  const token1 = tokenA.address === token0Address ? tokenB : tokenA
  const router02 = await(await ethers.getContractFactory('UniswapV2Router02')).deploy(factoryV2.address,WETH.address)
  return { pair, token0, token1, wallet, other, factoryV2, provider,router02 ,WETH}
}

  let DTT: Contract
  let WETH: Contract
  let router: Contract
  let pair: Contract
  let wallet :Wallet
  beforeEach(async function() {
    const fixture = await loadFixture(v2Fixture)

    WETH = fixture.WETH
    router = fixture.router02

    DTT = await (await ethers.getContractFactory("DeflatingERC20")).deploy(expandTo18Decimals(10000))
    wallet = fixture.wallet
    // make a DTT<>WETH pair
    await fixture.factoryV2.createPair(DTT.address, WETH.address,0)
    const pairAddress = await fixture.factoryV2.getPair(DTT.address, WETH.address)
    pair = new Contract(pairAddress, JSON.stringify(IUniswapV2Pair.abi), provider).connect(wallet)
  })

  afterEach(async function() {
    expect(await provider.getBalance(router.address)).to.eq(0)
  })

  async function addLiquidity(DTTAmount: BigNumber, WETHAmount: BigNumber) {
    await DTT.approve(router.address, ethers.constants.MaxUint256)
    await router.addLiquidityETH(DTT.address, DTTAmount, DTTAmount, WETHAmount, wallet.address, ethers.constants.MaxUint256, {
      value: WETHAmount
    })
  }

  it('removeLiquidityETHSupportingFeeOnTransferTokens', async () => {
    const DTTAmount = expandTo18Decimals(1)
    const ETHAmount = expandTo18Decimals(4)
    await addLiquidity(DTTAmount, ETHAmount)

    const DTTInPair = await DTT.balanceOf(pair.address)
    const WETHInPair = await WETH.balanceOf(pair.address)
    const liquidity = await pair.balanceOf(wallet.address)
    const totalSupply = await pair.totalSupply()
    const NaiveDTTExpected = DTTInPair.mul(liquidity).div(totalSupply)
    const WETHExpected = WETHInPair.mul(liquidity).div(totalSupply)

    await pair.approve(router.address, ethers.constants.MaxUint256)
    await router.removeLiquidityETHSupportingFeeOnTransferTokens(
      DTT.address,
      liquidity,
      NaiveDTTExpected,
      WETHExpected,
      wallet.address,
      ethers.constants.MaxUint256,
      overrides
    )
  })

  it('removeLiquidityETHWithPermitSupportingFeeOnTransferTokens', async () => {
    const DTTAmount = expandTo18Decimals(1)
      .mul(100)
      .div(99)
    const ETHAmount = expandTo18Decimals(4)
    await addLiquidity(DTTAmount, ETHAmount)

    const expectedLiquidity = expandTo18Decimals(2)

    const nonce = await pair.nonces(wallet.address)
    const digest = await getApprovalDigest(
      pair,
      { owner: wallet.address, spender: router.address, value: expectedLiquidity.sub(MINIMUM_LIQUIDITY) },
      nonce,
      ethers.constants.MaxUint256
    )
    const { v, r, s } = ecsign(Buffer.from(digest.slice(2), 'hex'), Buffer.from(wallet.privateKey.slice(2), 'hex'))

    const DTTInPair = await DTT.balanceOf(pair.address)
    const WETHInPair = await WETH.balanceOf(pair.address)
    const liquidity = await pair.balanceOf(wallet.address)
    const totalSupply = await pair.totalSupply()
    const NaiveDTTExpected = DTTInPair.mul(liquidity).div(totalSupply)
    const WETHExpected = WETHInPair.mul(liquidity).div(totalSupply)

    await pair.approve(router.address, ethers.constants.MaxUint256)
    await router.removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
      DTT.address,
      liquidity,
      NaiveDTTExpected,
      WETHExpected,
      wallet.address,
      ethers.constants.MaxUint256,
      false,
      v,
      r,
      s,
      overrides
    )
  })

  describe('swapExactTokensForTokensSupportingFeeOnTransferTokens', () => {
    const DTTAmount = expandTo18Decimals(5)
      .mul(100)
      .div(99)
    const ETHAmount = expandTo18Decimals(10)
    const amountIn = expandTo18Decimals(1)

    beforeEach(async () => {
      await addLiquidity(DTTAmount, ETHAmount)
    })

    it('DTT -> WETH', async () => {
      await DTT.approve(router.address, ethers.constants.MaxUint256)

      await router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
        amountIn,
        0,
        [DTT.address, WETH.address],
        wallet.address,
        ethers.constants.MaxUint256,
        
      )
    })

    // WETH -> DTT
    it('WETH -> DTT', async () => {
      await WETH.deposit({ value: amountIn }) // mint WETH
      await WETH.approve(router.address, ethers.constants.MaxUint256)

      await router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
        amountIn,
        0,
        [WETH.address, DTT.address],
        wallet.address,
        ethers.constants.MaxUint256,
        
      )
    })
  })

  // ETH -> DTT
  it('swapExactETHForTokensSupportingFeeOnTransferTokens', async () => {
    const DTTAmount = expandTo18Decimals(10)
      .mul(100)
      .div(99)
    const ETHAmount = expandTo18Decimals(5)
    const swapAmount = expandTo18Decimals(1)
    await addLiquidity(DTTAmount, ETHAmount)

    await router.swapExactETHForTokensSupportingFeeOnTransferTokens(
      0,
      [WETH.address, DTT.address],
      wallet.address,
      ethers.constants.MaxUint256,
      {
        value: swapAmount
      }
    )
  })

  // DTT -> ETH
  it('swapExactTokensForETHSupportingFeeOnTransferTokens', async () => {
    const DTTAmount = expandTo18Decimals(5)
      .mul(100)
      .div(99)
    const ETHAmount = expandTo18Decimals(10)
    const swapAmount = expandTo18Decimals(1)

    await addLiquidity(DTTAmount, ETHAmount)
    await DTT.approve(router.address, ethers.constants.MaxUint256)

    await router.swapExactTokensForETHSupportingFeeOnTransferTokens(
      swapAmount,
      0,
      [DTT.address, WETH.address],
      wallet.address,
      ethers.constants.MaxUint256
    )
  })
})

describe('fee-on-transfer tokens: reloaded', () => {
  const provider = ethers.getDefaultProvider();
  const loadFixture = waffle.createFixtureLoader(waffle.provider.getWallets(), waffle.provider)
	async function v2Fixture([wallet, other]: Wallet[], provider: MockProvider) {
  
    const factoryV2 = await deployContract(wallet,UniswapV2Factory,[wallet.address])
    const tokenA = await (await ethers.getContractFactory('ERC20')).deploy(expandTo18Decimals(1000000))
    const tokenB = await (await ethers.getContractFactory('ERC20')).deploy(expandTo18Decimals(1000000))
  
    await factoryV2.createPair(tokenA.address, tokenB.address, 200000)
  
    const contangoPairFactory = new ethers.ContractFactory(ContangoPair.abi,ContangoPair.bytecode)
    const pairAddress = await factoryV2.getPair(tokenA.address, tokenB.address)
    const pair = await ethers.getContractAt(ContangoPair.abi,pairAddress)
    const token0Address = await pair.token0()
    const WETH = await(await ethers.getContractFactory('WETH9')).deploy()
    const token0 = tokenA.address === token0Address ? tokenA : tokenB
    const token1 = tokenA.address === token0Address ? tokenB : tokenA
    const router02 = await(await ethers.getContractFactory('UniswapV2Router02')).deploy(factoryV2.address,WETH.address)
    return { pair, token0, token1, wallet, other, factoryV2, provider,router02 ,WETH}
  }

  let DTT: Contract
  let DTT2: Contract
  let router: Contract
  let wallet :Wallet
  beforeEach(async function() {
    const fixture = await loadFixture(v2Fixture)

    router = fixture.router02

    DTT =await (await ethers.getContractFactory("DeflatingERC20")).deploy(expandTo18Decimals(10000))
    DTT2 =await (await ethers.getContractFactory("DeflatingERC20")).deploy(expandTo18Decimals(10000))

    // make a DTT<>WETH pair
    await fixture.factoryV2.createPair(DTT.address, DTT2.address,0)
    wallet = fixture.wallet
    const pairAddress = await fixture.factoryV2.getPair(DTT.address, DTT2.address)
  })

  afterEach(async function() {
    expect(await provider.getBalance(router.address)).to.eq(0)
  })

  async function addLiquidity(DTTAmount: BigNumber, DTT2Amount: BigNumber) {
    await DTT.approve(router.address, ethers.constants.MaxUint256)
    await DTT2.approve(router.address, ethers.constants.MaxUint256)
    await router.addLiquidity(
      DTT.address,
      DTT2.address,
      DTTAmount,
      DTT2Amount,
      DTTAmount,
      DTT2Amount,
      wallet.address,
      ethers.constants.MaxUint256,
      overrides
    )
  }

  describe('swapExactTokensForTokensSupportingFeeOnTransferTokens', () => {
    const DTTAmount = expandTo18Decimals(5)
      .mul(100)
      .div(99)
    const DTT2Amount = expandTo18Decimals(5)
    const amountIn = expandTo18Decimals(1)

    beforeEach(async () => {
      await addLiquidity(DTTAmount, DTT2Amount)
    })

    it('DTT -> DTT2', async () => {
      await DTT.approve(router.address, ethers.constants.MaxUint256)

      await router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
        amountIn,
        0,
        [DTT.address, DTT2.address],
        wallet.address,
        ethers.constants.MaxUint256,
        overrides
      )
    })
  })
})
