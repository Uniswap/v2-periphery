import { HardhatUserConfig } from 'hardhat/types'
import '@nomiclabs/hardhat-waffle'

const config: HardhatUserConfig = {
  networks: {
    hardhat: {
      
      blockGasLimit: 20000000
    }
  },
  solidity: {
    version: '0.8.3',
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  }
}
export default config
