require('@nomiclabs/hardhat-ethers')
require('@nomiclabs/hardhat-etherscan')
// require("hardhat-contract-sizer");

require('dotenv').config({ path: '.env.local' })

module.exports = {
  solidity: '0.6.6',
  settings: {
    optimizer: {
      enabled: true,
      runs: 999999
    },
    evmVersion: 'istanbul',
    outputSelection: {
      '*': {
        '*': [
          'evm.bytecode.object',
          'evm.deployedBytecode.object',
          'abi',
          'evm.bytecode.sourceMap',
          'evm.deployedBytecode.sourceMap',
          'metadata'
        ],
        '': ['ast']
      }
    }
  },
  // contractSizer: {
  //   alphaSort: true,
  //   disambiguatePaths: false,
  //   runOnCompile: true,
  //   strict: true,
  //   // only: [':ERC20$'],
  // },
  networks: {
    arbitrumGoerli: {
      url: 'https://rpc.goerli.arbitrum.gateway.fm',
      accounts: [process.env.PRIVATE_KEY],
      allowUnlimitedContractSize: true,
    },
    goerli: {
      url: `https://goerli.infura.io/v3/${process.env.INFURA_PROJECT_ID}`,
      accounts: [process.env.PRIVATE_KEY],
      allowUnlimitedContractSize: true,
    }
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY
  }
}
