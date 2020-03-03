import chai, { expect } from 'chai'
import { Contract } from 'ethers'
import { MaxUint256 } from 'ethers/constants'
import { bigNumberify } from 'ethers/utils'
import { solidity, MockProvider, createFixtureLoader } from 'ethereum-waffle'

import { v2Fixture } from './shared/fixtures'
import { expandTo18Decimals } from './shared/utilities'

chai.use(solidity)

const MINIMUM_LIQUIDITY = bigNumberify(10).pow(3)

const overrides = {
  gasLimit: 9999999
}

describe('Migrator', () => {
  const provider = new MockProvider({
    hardfork: 'istanbul',
    mnemonic: 'horn horn horn horn horn horn horn horn horn horn horn horn',
    gasLimit: 9999999
  })
  const [wallet] = provider.getWallets()
  const loadFixture = createFixtureLoader(provider, [wallet])

  let WETH: Contract
  let WETHPartner: Contract
  let WETHExchange: Contract
  let router: Contract
  let migrator: Contract
  let exchange: Contract
  beforeEach(async function() {
    const fixture = await loadFixture(v2Fixture)
    WETH = fixture.WETH
    WETHPartner = fixture.WETHPartner
    WETHExchange = fixture.WETHExchange
    router = fixture.router
    migrator = fixture.migrator
    exchange = fixture.exchangeV1
  })

  it('router', async () => {
    expect(await migrator.router()).to.eq(router.address)
  })

  it('migrate', async () => {
    const WETHPartnerAmount = expandTo18Decimals(1)
    const ETHAmount = expandTo18Decimals(4)
    await WETHPartner.approve(exchange.address, MaxUint256)
    await exchange.addLiquidity(bigNumberify(1), WETHPartnerAmount, MaxUint256, { ...overrides, value: ETHAmount })
    await exchange.approve(migrator.address, MaxUint256)
    const expectedLiquidity = expandTo18Decimals(2)
    const WETHExchangeToken0 = await WETHExchange.token0()
    await expect(
      migrator.migrate(WETHPartner.address, WETHPartnerAmount, ETHAmount, wallet.address, MaxUint256, overrides)
    )
      // commented out because of this bug: https://github.com/EthWorks/Waffle/issues/100
      // .to.emit(WETHExchange, 'Transfer')
      // .withArgs(AddressZero, AddressZero, MINIMUM_LIQUIDITY)
      // .to.emit(WETHExchange, 'Transfer')
      // .withArgs(AddressZero, wallet.address, expectedLiquidity.sub(MINIMUM_LIQUIDITY))
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
    expect(await WETHExchange.balanceOf(wallet.address)).to.eq(expectedLiquidity.sub(MINIMUM_LIQUIDITY))
  })
})
