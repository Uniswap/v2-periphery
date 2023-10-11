const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  
  console.log("Deploying contracts with the account:", deployer.address);

  const factoryAddress = "0xc7a91efdD0f90A420fcAF11433C63B2cd59222FA";

  const UniswapV2Router01 = await hre.ethers.getContractFactory("UniswapV2Router01");
  const router = await UniswapV2Router01.deploy(factoryAddress, deployer.address);
  
  await router.deployed();
  
  console.log("UniswapV2Router01 deployed to:", router.address);

  // Verify the contract on Etherscan
  await hre.run("verify:verify", {
    address: router.address,
    constructorArguments: [factoryAddress, deployer.address],
  });
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
