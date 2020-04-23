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

describe.skip('ExampleFlashArbitrage', () => {
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

  describe('#arbitrage', () => {
    describe('token/WETH pairs', () => {
      let token0: string
      let token1: string
      beforeEach('sort tokens', () => {
        ([token0, token1] =
          WETH.address.toLowerCase() < WETHPartner.address.toLowerCase() ?
            [WETH.address, WETHPartner.address] : [WETHPartner.address, WETH.address])
      })

      describe('V1 eth is expensive', () => {
        beforeEach('add liquidity', async () => {
          // add liquidity to V1 at a rate of 1 ETH / 200 X
          const WETHPartnerAmountV1 = expandTo18Decimals(2000)
          const ETHAmountV1 = expandTo18Decimals(10)
          await WETHPartner.approve(WETHExchangeV1.address, WETHPartnerAmountV1)
          await WETHExchangeV1.addLiquidity(bigNumberify(1), WETHPartnerAmountV1, MaxUint256, {
            ...overrides,
            value: ETHAmountV1
          })

          // add liquidity to V2 at a rate of 1 ETH / 100 X
          const WETHPartnerAmountV2 = expandTo18Decimals(1000)
          const ETHAmountV2 = expandTo18Decimals(10)
          await WETHPartner.transfer(WETHPair.address, WETHPartnerAmountV2)
          await WETH.deposit({value: ETHAmountV2})
          await WETH.transfer(WETHPair.address, ETHAmountV2)
          await WETHPair.mint(wallet.address, overrides)
        })

        it('borrows eth from v2 to sell on v1', async () => {
          await expect(flashArbitrage.arbitrage(WETH.address, WETHPartner.address, wallet.address))
            .to.emit(flashArbitrage, 'Arbitrage')
            .withArgs(token0, token0 === WETH.address ? 0 : 99098, token1, token1 === WETH.address ? 0 : 99098)
        })
      })

      describe('V1 eth is cheap', () => {
        beforeEach('add liquidity', async () => {
          // add liquidity to V1 at a rate of 1 ETH / 50 X
          const WETHPartnerAmountV1 = expandTo18Decimals(500)
          const ETHAmountV1 = expandTo18Decimals(10)
          await WETHPartner.approve(WETHExchangeV1.address, WETHPartnerAmountV1)
          await WETHExchangeV1.addLiquidity(bigNumberify(1), WETHPartnerAmountV1, MaxUint256, {
            ...overrides,
            value: ETHAmountV1
          })

          // add liquidity to V2 at a rate of 1 ETH / 100 X
          const WETHPartnerAmountV2 = expandTo18Decimals(1000)
          const ETHAmountV2 = expandTo18Decimals(10)
          await WETHPartner.transfer(WETHPair.address, WETHPartnerAmountV2)
          await WETH.deposit({value: ETHAmountV2})
          await WETH.transfer(WETHPair.address, ETHAmountV2)
          await WETHPair.mint(wallet.address, overrides)
        })

        it('borrows tokens from v2 to sell on v1', async () => {
          await expect(flashArbitrage.arbitrage(WETH.address, WETHPartner.address, wallet.address))
            .to.emit(flashArbitrage, 'Arbitrage')
            .withArgs(token0, token0 === WETH.address ? 8 : 0, token1, token1 === WETH.address ? 8 : 0)
        })
      })
    })
  })
})
