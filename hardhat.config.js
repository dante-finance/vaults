require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-etherscan");
let secret = require("./secret"); 

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.1",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1000,
          },
        }
      }
    ]
  },
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true
    },
    localhost: {
      allowUnlimitedContractSize: true
    },
    testnet: {
      url: secret.url,
      accounts: [secret.key],
      gas: 10000000,
      blockGasLimit: 10000000,
      allowUnlimitedContractSize: true
    },
    mainnet: {
      url: secret.url,
      accounts: [secret.key],
      gas: "auto",
      gasPrice: "auto",
      gasMultiplier: 1,
      allowUnlimitedContractSize: false
    }
  },
  etherscan: {
    apiKey: "JSMN6FNUZR4X6VWI1GHZBXY1EA5BDRPV1R"
  }
};
