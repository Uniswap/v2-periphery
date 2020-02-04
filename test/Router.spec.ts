import chai, { expect } from 'chai'
import { Contract } from 'ethers'
import { Zero, MaxUint256 } from 'ethers/constants'
import { BigNumber, bigNumberify } from 'ethers/utils'
import { solidity, MockProvider, createFixtureLoader, deployContract } from 'ethereum-waffle'
import { ecsign } from 'ethereumjs-util'

import { expandTo18Decimals, getApprovalDigest } from './shared/utilities'
import { exchangeFixture } from './shared/fixtures'

import Router from '../build/Router.json'

chai.use(solidity)

const overrides = {
  gasLimit: 9999999
}

describe('Router', () => {
  const provider = new MockProvider({
    hardfork: 'istanbul',
    mnemonic: 'horn horn horn horn horn horn horn horn horn horn horn horn',
    gasLimit: 9999999
  })
  const [wallet] = provider.getWallets()
  const loadFixture = createFixtureLoader(provider, [wallet])

  let factory: Contract
  let token0: Contract
  let token1: Contract
  let exchange: Contract
  let WETH: Contract
  let WETHPartner: Contract
  let WETHExchange: Contract
  let router: Contract
  beforeEach(async function() {
    const fixture = await loadFixture(exchangeFixture)
    factory = fixture.factory
    token0 = fixture.token0
    token1 = fixture.token1
    exchange = fixture.exchange
    WETH = fixture.WETH
    WETHPartner = fixture.WETHPartner
    WETHExchange = fixture.WETHExchange

    router = await deployContract(wallet, Router, [factory.address, WETH.address], overrides)
  })

  afterEach(async function() {
    expect(await provider.getBalance(router.address)).to.eq(Zero)
  })

  it('factory, WETH', async () => {
    expect(await router.factory()).to.eq(factory.address)
    expect(await router.WETH()).to.eq(WETH.address)
  })

  it('addLiquidity', async () => {
    const token0Amount = expandTo18Decimals(1)
    const token1Amount = expandTo18Decimals(4)

    const expectedLiquidity = expandTo18Decimals(2)
    await token0.approve(router.address, MaxUint256)
    await token1.approve(router.address, MaxUint256)
    await expect(
      router.addLiquidity(
        token0.address,
        token1.address,
        token0Amount,
        token1Amount,
        0,
        0,
        wallet.address,
        MaxUint256,
        overrides
      )
    )
      // commented out because of this bug: https://github.com/EthWorks/Waffle/issues/100
      // .to.emit(exchange, 'Transfer')
      // .withArgs(AddressZero, wallet.address, expectedLiquidity)
      .to.emit(exchange, 'Sync')
      .withArgs(token0Amount, token1Amount)
      .to.emit(exchange, 'Mint')
      .withArgs(router.address, token0Amount, token1Amount)

    expect(await exchange.balanceOf(wallet.address)).to.eq(expectedLiquidity)
  })

  it('addLiquidityETH', async () => {
    const WETHPartnerAmount = expandTo18Decimals(1)
    const ETHAmount = expandTo18Decimals(4)

    const expectedLiquidity = expandTo18Decimals(2)
    const WETHExchangeToken0 = await WETHExchange.token0()
    await WETHPartner.approve(router.address, MaxUint256)
    await expect(
      router.addLiquidityETH(
        WETHPartner.address,
        WETHPartnerAmount,
        WETHPartnerAmount,
        ETHAmount,
        wallet.address,
        MaxUint256,
        { ...overrides, value: ETHAmount }
      )
    )
      // commented out because of this bug: https://github.com/EthWorks/Waffle/issues/100
      // .to.emit(WETHExchange, 'Transfer')
      // .withArgs(AddressZero, wallet.address, expectedLiquidity)
      .to.emit(WETHExchange, 'Sync')
      .withArgs(
        WETHExchangeToken0 === WETHPartner.address ? WETHPartnerAmount : ETHAmount,
        WETHExchangeToken0 === WETHPartner.address ? ETHAmount : WETHPartnerAmount
      )
      .to.emit(WETHExchange, 'Mint')
      .withArgs(
        router.address,
        WETHExchangeToken0 === WETHPartner.address ? WETHPartnerAmount : ETHAmount,
        WETHExchangeToken0 === WETHPartner.address ? ETHAmount : WETHPartnerAmount
      )

    expect(await WETHExchange.balanceOf(wallet.address)).to.eq(expectedLiquidity)
  })

  async function addLiquidity(token0Amount: BigNumber, token1Amount: BigNumber) {
    await token0.transfer(exchange.address, token0Amount)
    await token1.transfer(exchange.address, token1Amount)
    await exchange.mint(wallet.address, overrides)
  }
  it('removeLiquidity', async () => {
    const token0Amount = expandTo18Decimals(1)
    const token1Amount = expandTo18Decimals(4)
    await addLiquidity(token0Amount, token1Amount)

    const expectedLiquidity = expandTo18Decimals(2)
    await exchange.approve(router.address, MaxUint256)
    await expect(
      router.removeLiquidity(
        token0.address,
        token1.address,
        expectedLiquidity,
        0,
        0,
        wallet.address,
        MaxUint256,
        overrides
      )
    )
      .to.emit(exchange, 'Transfer')
      .withArgs(wallet.address, exchange.address, expectedLiquidity)
      // commented out because of this bug: https://github.com/EthWorks/Waffle/issues/100
      // .to.emit(exchange, 'Transfer')
      // .withArgs(exchange.address, AddressZero, expectedLiquidity)
      // .to.emit(token0, 'Transfer')
      // .withArgs(exchange.address, wallet.address, token0Amount)
      // .to.emit(token1, 'Transfer')
      // .withArgs(exchange.address, wallet.address, token1Amount)
      .to.emit(exchange, 'Sync')
      .withArgs(0, 0)
      .to.emit(exchange, 'Burn')
      .withArgs(router.address, token0Amount, token1Amount, wallet.address)

    expect(await exchange.balanceOf(wallet.address)).to.eq(0)
    const totalSupplyToken0 = await token0.totalSupply()
    const totalSupplyToken1 = await token1.totalSupply()
    expect(await token0.balanceOf(wallet.address)).to.eq(totalSupplyToken0)
    expect(await token1.balanceOf(wallet.address)).to.eq(totalSupplyToken1)
  })

  it('removeLiquidityETH', async () => {
    const WETHPartnerAmount = expandTo18Decimals(1)
    const ETHAmount = expandTo18Decimals(4)
    await WETHPartner.transfer(WETHExchange.address, WETHPartnerAmount)
    await WETH.deposit({ value: ETHAmount })
    await WETH.transfer(WETHExchange.address, ETHAmount)
    await WETHExchange.mint(wallet.address, overrides)

    const expectedLiquidity = expandTo18Decimals(2)
    const WETHExchangeToken0 = await WETHExchange.token0()
    await WETHExchange.approve(router.address, MaxUint256)
    await expect(
      router.removeLiquidityETH(WETHPartner.address, expectedLiquidity, 0, 0, wallet.address, MaxUint256, overrides)
    )
      .to.emit(WETHExchange, 'Transfer')
      .withArgs(wallet.address, WETHExchange.address, expectedLiquidity)
      // commented out because of this bug: https://github.com/EthWorks/Waffle/issues/100
      // .to.emit(WETHExchange, 'Transfer')
      // .withArgs(WETHExchange.address, AddressZero, expectedLiquidity)
      // .to.emit(WETHPartner, 'Transfer')
      // .withArgs(WETHExchange.address, router.address, WETHPartnerAmount)
      // .to.emit(WETH, 'Transfer')
      // .withArgs(WETHExchange.address, router.address, ETHAmount)
      // .to.emit(WETHPartner, 'Transfer')
      // .withArgs(router.address, wallet.address, WETHPartnerAmount)
      .to.emit(WETHExchange, 'Sync')
      .withArgs(0, 0)
      .to.emit(WETHExchange, 'Burn')
      .withArgs(
        router.address,
        WETHExchangeToken0 === WETHPartner.address ? WETHPartnerAmount : ETHAmount,
        WETHExchangeToken0 === WETHPartner.address ? ETHAmount : WETHPartnerAmount,
        router.address
      )

    expect(await WETHExchange.balanceOf(wallet.address)).to.eq(0)
    const totalSupplyToken0 = await token0.totalSupply()
    const totalSupplyToken1 = await token1.totalSupply()
    expect(await token0.balanceOf(wallet.address)).to.eq(totalSupplyToken0)
    expect(await token1.balanceOf(wallet.address)).to.eq(totalSupplyToken1)
  })

  it('removeLiquidityWithPermit', async () => {
    const token0Amount = expandTo18Decimals(1)
    const token1Amount = expandTo18Decimals(4)
    await addLiquidity(token0Amount, token1Amount)

    const expectedLiquidity = expandTo18Decimals(2)

    const nonce = await exchange.nonces(wallet.address)
    const digest = await getApprovalDigest(
      exchange,
      { owner: wallet.address, spender: router.address, value: expectedLiquidity },
      nonce,
      MaxUint256
    )

    const { v, r, s } = ecsign(Buffer.from(digest.slice(2), 'hex'), Buffer.from(wallet.privateKey.slice(2), 'hex'))

    await router.removeLiquidityWithPermit(
      token0.address,
      token1.address,
      expectedLiquidity,
      0,
      0,
      wallet.address,
      MaxUint256,
      v,
      r,
      s,
      overrides
    )
  })

  it('removeLiquidityETHWithPermit', async () => {
    const WETHPartnerAmount = expandTo18Decimals(1)
    const ETHAmount = expandTo18Decimals(4)
    await WETHPartner.transfer(WETHExchange.address, WETHPartnerAmount)
    await WETH.deposit({ value: ETHAmount })
    await WETH.transfer(WETHExchange.address, ETHAmount)
    await WETHExchange.mint(wallet.address, overrides)

    const expectedLiquidity = expandTo18Decimals(2)

    const nonce = await WETHExchange.nonces(wallet.address)
    const digest = await getApprovalDigest(
      WETHExchange,
      { owner: wallet.address, spender: router.address, value: expectedLiquidity },
      nonce,
      MaxUint256
    )

    const { v, r, s } = ecsign(Buffer.from(digest.slice(2), 'hex'), Buffer.from(wallet.privateKey.slice(2), 'hex'))

    await router.removeLiquidityETHWithPermit(
      WETHPartner.address,
      expectedLiquidity,
      0,
      0,
      wallet.address,
      MaxUint256,
      v,
      r,
      s,
      overrides
    )
  })

  it('swapExactTokensForTokens', async () => {
    const token0Amount = expandTo18Decimals(5)
    const token1Amount = expandTo18Decimals(10)
    await addLiquidity(token0Amount, token1Amount)

    const swapAmount = expandTo18Decimals(1)
    const expectedOutputAmount = bigNumberify('1662497915624478906')
    await token0.approve(router.address, MaxUint256)
    await expect(
      router.swapExactTokensForTokens(
        swapAmount,
        0,
        [token0.address, token1.address],
        wallet.address,
        MaxUint256,
        overrides
      )
    )
      .to.emit(token0, 'Transfer')
      .withArgs(wallet.address, exchange.address, swapAmount)
      // commented out because of this bug: https://github.com/EthWorks/Waffle/issues/100
      // .to.emit(token1, 'Transfer')
      // .withArgs(exchange.address, wallet.address, expectedOutputAmount)
      .to.emit(exchange, 'Sync')
      .withArgs(token0Amount.add(swapAmount), token1Amount.sub(expectedOutputAmount))
      .to.emit(exchange, 'Swap')
      .withArgs(router.address, token0.address, swapAmount, expectedOutputAmount, wallet.address)
  })

  it('swapTokensForExactTokens', async () => {
    const token0Amount = expandTo18Decimals(5)
    const token1Amount = expandTo18Decimals(10)
    await addLiquidity(token0Amount, token1Amount)

    const expectedSwapAmount = bigNumberify('557227237267357629')
    const outputAmount = expandTo18Decimals(1)
    await token0.approve(router.address, MaxUint256)
    await expect(
      router.swapTokensForExactTokens(
        outputAmount,
        MaxUint256,
        [token0.address, token1.address],
        wallet.address,
        MaxUint256,
        overrides
      )
    )
      .to.emit(token0, 'Transfer')
      .withArgs(wallet.address, exchange.address, expectedSwapAmount)
      // commented out because of this bug: https://github.com/EthWorks/Waffle/issues/100
      // .to.emit(token1, 'Transfer')
      // .withArgs(exchange.address, wallet.address, outputAmount)
      .to.emit(exchange, 'Sync')
      .withArgs(token0Amount.add(expectedSwapAmount), token1Amount.sub(outputAmount))
      .to.emit(exchange, 'Swap')
      .withArgs(router.address, token0.address, expectedSwapAmount, outputAmount, wallet.address)
  })

  it('swapExactETHForTokens', async () => {
    const WETHPartnerAmount = expandTo18Decimals(10)
    const ETHAmount = expandTo18Decimals(5)
    await WETHPartner.transfer(WETHExchange.address, WETHPartnerAmount)
    await WETH.deposit({ value: ETHAmount })
    await WETH.transfer(WETHExchange.address, ETHAmount)
    await WETHExchange.mint(wallet.address, overrides)

    const swapAmount = expandTo18Decimals(1)
    const expectedOutputAmount = bigNumberify('1662497915624478906')
    const WETHExchangeToken0 = await WETHExchange.token0()
    await expect(
      router.swapExactETHForTokens(0, [WETH.address, WETHPartner.address], wallet.address, MaxUint256, {
        ...overrides,
        value: swapAmount
      })
    )
      .to.emit(WETH, 'Transfer')
      .withArgs(router.address, WETHExchange.address, swapAmount)
      // commented out because of this bug: https://github.com/EthWorks/Waffle/issues/100
      // .to.emit(WETHPartner, 'Transfer')
      // .withArgs(WETHExchange.address, wallet.address, expectedOutputAmount)
      .to.emit(WETHExchange, 'Sync')
      .withArgs(
        WETHExchangeToken0 === WETHPartner.address
          ? WETHPartnerAmount.sub(expectedOutputAmount)
          : ETHAmount.add(swapAmount),
        WETHExchangeToken0 === WETHPartner.address
          ? ETHAmount.add(swapAmount)
          : WETHPartnerAmount.sub(expectedOutputAmount)
      )
      .to.emit(WETHExchange, 'Swap')
      .withArgs(router.address, WETH.address, swapAmount, expectedOutputAmount, wallet.address)
  })

  it('swapTokensForExactETH', async () => {
    const WETHPartnerAmount = expandTo18Decimals(5)
    const ETHAmount = expandTo18Decimals(10)
    await WETHPartner.transfer(WETHExchange.address, WETHPartnerAmount)
    await WETH.deposit({ value: ETHAmount })
    await WETH.transfer(WETHExchange.address, ETHAmount)
    await WETHExchange.mint(wallet.address, overrides)

    const expectedSwapAmount = bigNumberify('557227237267357629')
    const outputAmount = expandTo18Decimals(1)
    await WETHPartner.approve(router.address, MaxUint256)
    const WETHExchangeToken0 = await WETHExchange.token0()
    await expect(
      router.swapTokensForExactETH(
        outputAmount,
        MaxUint256,
        [WETHPartner.address, WETH.address],
        wallet.address,
        MaxUint256,
        overrides
      )
    )
      .to.emit(WETHPartner, 'Transfer')
      .withArgs(wallet.address, WETHExchange.address, expectedSwapAmount)
      // commented out because of this bug: https://github.com/EthWorks/Waffle/issues/100
      // .to.emit(WETHPartner, 'Transfer')
      // .withArgs(WETHExchange.address, router.address, outputAmount)
      .to.emit(WETHExchange, 'Sync')
      .withArgs(
        WETHExchangeToken0 === WETHPartner.address
          ? WETHPartnerAmount.add(expectedSwapAmount)
          : ETHAmount.sub(outputAmount),
        WETHExchangeToken0 === WETHPartner.address
          ? ETHAmount.sub(outputAmount)
          : WETHPartnerAmount.add(expectedSwapAmount)
      )
      .to.emit(WETHExchange, 'Swap')
      .withArgs(router.address, WETHPartner.address, expectedSwapAmount, outputAmount, router.address)
  })

  it('swapExactTokensForETH', async () => {
    const WETHPartnerAmount = expandTo18Decimals(5)
    const ETHAmount = expandTo18Decimals(10)
    await WETHPartner.transfer(WETHExchange.address, WETHPartnerAmount)
    await WETH.deposit({ value: ETHAmount })
    await WETH.transfer(WETHExchange.address, ETHAmount)
    await WETHExchange.mint(wallet.address, overrides)

    const swapAmount = expandTo18Decimals(1)
    const expectedOutputAmount = bigNumberify('1662497915624478906')
    await WETHPartner.approve(router.address, MaxUint256)
    const WETHExchangeToken0 = await WETHExchange.token0()
    await expect(
      router.swapExactTokensForETH(
        swapAmount,
        0,
        [WETHPartner.address, WETH.address],
        wallet.address,
        MaxUint256,
        overrides
      )
    )
      .to.emit(WETHPartner, 'Transfer')
      .withArgs(wallet.address, WETHExchange.address, swapAmount)
      // commented out because of this bug: https://github.com/EthWorks/Waffle/issues/100
      // .to.emit(WETH, 'Transfer')
      // .withArgs(WETHExchange.address, router.address, expectedOutputAmount)
      .to.emit(exchange, 'Sync')
      .withArgs(
        WETHExchangeToken0 === WETHPartner.address
          ? WETHPartnerAmount.add(swapAmount)
          : ETHAmount.sub(expectedOutputAmount),
        WETHExchangeToken0 === WETHPartner.address
          ? ETHAmount.sub(expectedOutputAmount)
          : WETHPartnerAmount.add(swapAmount)
      )
      .to.emit(exchange, 'Swap')
      .withArgs(router.address, WETHPartner.address, swapAmount, expectedOutputAmount, router.address)
  })

  it('swapETHForExactTokens', async () => {
    const WETHPartnerAmount = expandTo18Decimals(10)
    const ETHAmount = expandTo18Decimals(5)
    await WETHPartner.transfer(WETHExchange.address, WETHPartnerAmount)
    await WETH.deposit({ value: ETHAmount })
    await WETH.transfer(WETHExchange.address, ETHAmount)
    await WETHExchange.mint(wallet.address, overrides)

    const expectedSwapAmount = bigNumberify('557227237267357629')
    const outputAmount = expandTo18Decimals(1)
    const WETHExchangeToken0 = await WETHExchange.token0()
    await expect(
      router.swapETHForExactTokens(outputAmount, [WETH.address, WETHPartner.address], wallet.address, MaxUint256, {
        ...overrides,
        value: expectedSwapAmount
      })
    )
      .to.emit(WETH, 'Transfer')
      .withArgs(router.address, WETHExchange.address, expectedSwapAmount)
      // commented out because of this bug: https://github.com/EthWorks/Waffle/issues/100
      // .to.emit(WETHPartner, 'Transfer')
      // .withArgs(exchange.address, wallet.address, outputAmount)
      .to.emit(WETHExchange, 'Sync')
      .withArgs(
        WETHExchangeToken0 === WETHPartner.address
          ? WETHPartnerAmount.sub(outputAmount)
          : ETHAmount.add(expectedSwapAmount),
        WETHExchangeToken0 === WETHPartner.address
          ? ETHAmount.add(expectedSwapAmount)
          : WETHPartnerAmount.sub(outputAmount)
      )
      .to.emit(WETHExchange, 'Swap')
      .withArgs(router.address, WETH.address, expectedSwapAmount, outputAmount, wallet.address)
  })
})
