require("@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-etherscan");

require("dotenv").config({ path: ".env.local" });

module.exports = {
  solidity: "0.6.6",
  networks: {
    arbitrumGoerli: {
      url: "https://arbitrum-goerli.public.blastapi.io",
      accounts: [process.env.PRIVATE_KEY],
    },
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
};
