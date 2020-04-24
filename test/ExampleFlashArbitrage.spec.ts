import chai, { expect } from 'chai'
import { Contract } from 'ethers'
import { MaxUint256 } from 'ethers/constants'
import { BigNumber, bigNumberify, defaultAbiCoder, formatEther } from 'ethers/utils'
import { solidity, MockProvider, createFixtureLoader, deployContract } from 'ethereum-waffle'

import { expandTo18Decimals } from './shared/utilities'
import { v2Fixture } from './shared/fixtures'

import ExampleFlashArbitrage from '../build/ExampleFlashArbitrage.json'

chai.use(solidity)

const overrides = {
  gasLimit: 9999999
}

describe.only('ExampleFlashArbitrage', () => {
  const provider = new MockProvider({
    hardfork: 'istanbul',
    mnemonic: 'horn horn horn horn horn horn horn horn horn horn horn horn',
    gasLimit: 9999999
  })
  const [wallet] = provider.getWallets()
  const loadFixture = createFixtureLoader(provider, [wallet])

  let WETH: Contract
  let WETHPartner: Contract
  let WETHExchangeV1: Contract
  let WETHPair: Contract
  let flashArbitrage: Contract
  beforeEach(async function() {
    const fixture = await loadFixture(v2Fixture)

    WETH = fixture.WETH
    WETHPartner = fixture.WETHPartner
    WETHExchangeV1 = fixture.WETHExchangeV1
    WETHPair = fixture.WETHPair
    flashArbitrage = await deployContract(
      wallet,
      ExampleFlashArbitrage,
      [fixture.factoryV1.address, fixture.factoryV2.address, WETH.address],
      overrides
    )
  })

  async function setupEthLiquidity({
    v1Eth,
    v1Token,
    v2Eth,
    v2Token
  }: {
    v1Eth: number
    v1Token: number
    v2Eth: number
    v2Token: number
  }) {
    // add liquidity to V1 at a rate of 1 ETH / 10 X
    const WETHPartnerAmountV1 = expandTo18Decimals(v1Token)
    const ETHAmountV1 = expandTo18Decimals(v1Eth)
    await WETHPartner.approve(WETHExchangeV1.address, WETHPartnerAmountV1)
    await WETHExchangeV1.addLiquidity(bigNumberify(1), WETHPartnerAmountV1, MaxUint256, {
      ...overrides,
      value: ETHAmountV1
    })

    // add liquidity to V2 at a rate of 1 ETH / 5 X
    const WETHPartnerAmountV2 = expandTo18Decimals(v2Token)
    const ETHAmountV2 = expandTo18Decimals(v2Eth)
    await WETHPartner.transfer(WETHPair.address, WETHPartnerAmountV2)
    await WETH.deposit({ value: ETHAmountV2 })
    await WETH.transfer(WETHPair.address, ETHAmountV2)
    await WETHPair.mint(wallet.address, overrides)
  }

  describe('#arbitrage', () => {
    describe('token/WETH pairs', () => {
      let token0: string
      let token1: string
      beforeEach('sort tokens', () => {
        ;[token0, token1] =
          WETH.address.toLowerCase() < WETHPartner.address.toLowerCase()
            ? [WETH.address, WETHPartner.address]
            : [WETHPartner.address, WETH.address]
      })

      describe('V1 eth is expensive', () => {
        describe('more liquidity in V1 than V2', () => {
          beforeEach(async () => {
            await setupEthLiquidity({
              v1Eth: 1,
              v1Token: 10,
              v2Eth: 1,
              v2Token: 5
            })
          })

          it('creates optimal profit', async () => {
            await expect(flashArbitrage.arbitrage(WETH.address, WETHPartner.address, wallet.address)).to.emit(
              flashArbitrage,
              'Arbitrage'
            )
          })
        })

        describe('less liquidity in V1 than V2', () => {
          beforeEach(async () => {
            await setupEthLiquidity({
              v1Eth: 1,
              v1Token: 10,
              v2Eth: 2,
              v2Token: 10
            })
          })

          it('creates optimal profit', async () => {
            await expect(flashArbitrage.arbitrage(WETH.address, WETHPartner.address, wallet.address)).to.emit(
              flashArbitrage,
              'Arbitrage'
            )
          })
        })

        describe('same liquidity in V1 and V2', () => {
          beforeEach(async () => {
            await setupEthLiquidity({
              v1Eth: 1,
              v1Token: 10,
              v2Eth: 2,
              v2Token: 5
            })
          })

          it('creates optimal profit', async () => {
            await expect(flashArbitrage.arbitrage(WETH.address, WETHPartner.address, wallet.address)).to.emit(
              flashArbitrage,
              'Arbitrage'
            )
          })
        })
      })

      describe('V1 eth is cheap', () => {
        describe('more liquidity in V1 than V2', () => {
          beforeEach(async () => {
            await setupEthLiquidity({
              v1Eth: 2,
              v1Token: 10,
              v2Eth: 1,
              v2Token: 10
            })
          })

          it('creates optimal profit', async () => {
            await expect(flashArbitrage.arbitrage(WETH.address, WETHPartner.address, wallet.address)).to.emit(
              flashArbitrage,
              'Arbitrage'
            )
          })
        })

        describe('less liquidity in V1 than V2', () => {
          beforeEach(async () => {
            await setupEthLiquidity({
              v1Eth: 1,
              v1Token: 5,
              v2Eth: 1,
              v2Token: 10
            })
          })

          it('creates optimal profit', async () => {
            await expect(flashArbitrage.arbitrage(WETH.address, WETHPartner.address, wallet.address)).to.emit(
              flashArbitrage,
              'Arbitrage'
            )
          })
        })

        describe('same liquidity in V1 and V2', () => {
          beforeEach(async () => {
            await setupEthLiquidity({
              v1Eth: 2,
              v1Token: 5,
              v2Eth: 1,
              v2Token: 10
            })
          })

          it('creates optimal profit', async () => {
            await expect(flashArbitrage.arbitrage(WETH.address, WETHPartner.address, wallet.address)).to.emit(
              flashArbitrage,
              'Arbitrage'
            )
          })
        })
      })
    })
  })
})
