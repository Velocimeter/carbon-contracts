import { NamedAccounts } from './data/named-accounts';
import { DeploymentNetwork } from './utils/Constants';
import './test/Setup';
import '@nomiclabs/hardhat-ethers';
import '@nomiclabs/hardhat-etherscan';
import '@nomiclabs/hardhat-solhint';
import '@nomiclabs/hardhat-waffle';
import '@tenderly/hardhat-tenderly';
import '@typechain/hardhat';
import 'dotenv/config';
import 'hardhat-contract-sizer';
import 'hardhat-dependency-compiler';
import 'hardhat-deploy';
import 'hardhat-storage-layout';
import 'hardhat-watcher';
import { HardhatUserConfig } from 'hardhat/config';
import { MochaOptions } from 'mocha';
import 'solidity-coverage';

interface EnvOptions {
    ETHEREUM_PROVIDER_URL?: string;
    ETHEREUM_RINKEBY_PROVIDER_URL?: string;
    ETHERSCAN_API_KEY?: string;
    GAS_PRICE?: number | 'auto';
    NIGHTLY?: boolean;
    PROFILE?: boolean;
    TENDERLY_FORK_ID?: string;
    TENDERLY_PROJECT?: string;
    TENDERLY_TEST_PROJECT?: string;
    TENDERLY_USERNAME?: string;
    FANTOM_PROVIDER_URL?: string;
    BASE_PROVIDER_URL?: string;
    CANTO_PROVIDER_URL?: string;
    ARBITRUM_PROVIDER_URL?: string;
    MANTLE_PROVIDER_URL?: string;
    ZKSYNC_PROVIDER_URL?: string;
    GNOSIS_PROVIDER_URL?: string;
    BSC_PROVIDER_URL?: string;
    BASE_GOERLI_PROVIDER_URL?: string;
    SCROLL_PROVIDER_URL?: string;
    BERA_ARTIO_PROVIDER_URL?: string;
    NEON_DEVNET_PROVIDER_URL?: string;
    NEON_MAINNET_PROVIDER_URL?: string;
    SANKO_TESTNET_PROVIDER_URL?: string;
    TELOS_PROVIDER_URL?: string;
    PRIVATE_KEY?: string;
}

const {
    ETHEREUM_PROVIDER_URL = '',
    ETHEREUM_RINKEBY_PROVIDER_URL = '',
    ETHERSCAN_API_KEY = '',
    GAS_PRICE: gasPrice = 'auto',
    NIGHTLY: isNightly,
    PROFILE: isProfiling,
    TENDERLY_FORK_ID = '',
    TENDERLY_PROJECT = '',
    TENDERLY_TEST_PROJECT = '',
    TENDERLY_USERNAME = '',
    FANTOM_PROVIDER_URL = '',
    BASE_PROVIDER_URL = '',
    CANTO_PROVIDER_URL = '',
    ARBITRUM_PROVIDER_URL = '',
    MANTLE_PROVIDER_URL = '',
    ZKSYNC_PROVIDER_URL = '',
    GNOSIS_PROVIDER_URL = '',
    BSC_PROVIDER_URL = '',
    BASE_GOERLI_PROVIDER_URL = '',
    SCROLL_PROVIDER_URL = '',
    BERA_ARTIO_PROVIDER_URL = '',
    NEON_DEVNET_PROVIDER_URL = '',
    NEON_MAINNET_PROVIDER_URL = '',
    SANKO_TESTNET_PROVIDER_URL = '',
    TELOS_PROVIDER_URL = '',
    PRIVATE_KEY = ''
}: EnvOptions = process.env as any as EnvOptions;

const mochaOptions = (): MochaOptions => {
    let timeout = 600000;
    let grep = '';
    let reporter;
    let invert = false;

    return {
        timeout,
        color: true,
        bail: true,
        grep,
        invert,
        reporter
    };
};

const config: HardhatUserConfig = {
    networks: {
        [DeploymentNetwork.Hardhat]: {
            accounts: {
                count: 20,
                accountsBalance: '10000000000000000000000000000000000000000000000'
            },
            allowUnlimitedContractSize: true,
            saveDeployments: false,
            live: false
        },
        [DeploymentNetwork.Mainnet]: {
            chainId: 1,
            url: ETHEREUM_PROVIDER_URL,
            // gasPrice,
            saveDeployments: true,
            live: true
        },
        [DeploymentNetwork.Rinkeby]: {
            chainId: 4,
            url: ETHEREUM_RINKEBY_PROVIDER_URL,
            saveDeployments: true,
            live: true
        },
        [DeploymentNetwork.Tenderly]: {
            chainId: 1,
            url: `https://rpc.tenderly.co/fork/${TENDERLY_FORK_ID}`,
            autoImpersonate: true,
            saveDeployments: true,
            live: true,
            gas: 6000000
        },
        [DeploymentNetwork.Fantom]: {
            chainId: 250,
            url: FANTOM_PROVIDER_URL,
            accounts: [PRIVATE_KEY],
            // gasPrice,
            saveDeployments: true,
            live: true
        },
        [DeploymentNetwork.Base]: {
            chainId: 8453,
            url: BASE_PROVIDER_URL,
            // gasPrice,
            saveDeployments: true,
            live: true
        },
        [DeploymentNetwork.Canto]: {
            chainId: 7700,
            url: CANTO_PROVIDER_URL,
            // gasPrice,
            saveDeployments: true,
            live: true
        },
        [DeploymentNetwork.Arbitrum]: {
            chainId: 42161,
            url: ARBITRUM_PROVIDER_URL,
            accounts: [PRIVATE_KEY],
            // gasPrice,
            saveDeployments: true,
            live: true
        },
        [DeploymentNetwork.Mantle]: {
            chainId: 5000,
            url: MANTLE_PROVIDER_URL,
            accounts: [PRIVATE_KEY],
            // gasPrice,
            saveDeployments: true,
            live: true
        },
        [DeploymentNetwork.ZkSync]: {
            chainId: 324,
            url: ZKSYNC_PROVIDER_URL,
            accounts: [PRIVATE_KEY],
            // gasPrice,
            saveDeployments: true,
            live: true
        },
        [DeploymentNetwork.Gnosis]: {
            chainId: 100,
            url: GNOSIS_PROVIDER_URL,
            accounts: [PRIVATE_KEY],
            // gasPrice,
            saveDeployments: true,
            live: true
        },
        [DeploymentNetwork.Bsc]: {
            chainId: 56,
            url: BSC_PROVIDER_URL,
            accounts: [PRIVATE_KEY],
            // gasPrice,
            saveDeployments: true,
            live: true
        },
        [DeploymentNetwork.BaseGoerli]: {
            chainId: 84531,
            url: BASE_GOERLI_PROVIDER_URL,
            accounts: [PRIVATE_KEY],
            // gasPrice,
            saveDeployments: true,
            live: true
        },
        [DeploymentNetwork.Scroll]: {
            chainId: 534352,
            url: SCROLL_PROVIDER_URL,
            accounts: [PRIVATE_KEY],
            // gasPrice,
            saveDeployments: true,
            live: true
        },
        [DeploymentNetwork.BeraArtio]: {
            chainId: 80085,
            url: BERA_ARTIO_PROVIDER_URL,
            accounts: [PRIVATE_KEY],
            // gasPrice,
            saveDeployments: true,
            live: true
        },
        [DeploymentNetwork.NeonDevnet]: {
            chainId: 245022926,
            url: NEON_DEVNET_PROVIDER_URL,
            accounts: [PRIVATE_KEY],
            // gasPrice,
            saveDeployments: true,
            live: true
        },
        [DeploymentNetwork.NeonMainnet]: {
            chainId: 245022934,
            url: NEON_MAINNET_PROVIDER_URL,
            accounts: [PRIVATE_KEY],
            // gasPrice,
            saveDeployments: true,
            live: true
        },
        [DeploymentNetwork.SankoTestnet]: {
            chainId: 1992,
            url: SANKO_TESTNET_PROVIDER_URL,
            accounts: [PRIVATE_KEY],
            // gasPrice,
            saveDeployments: true,
            live: true
        },
        [DeploymentNetwork.Telos]: {
            chainId: 40,
            url: TELOS_PROVIDER_URL,
            accounts: [PRIVATE_KEY],
            gas: 3000000000,
            gasPrice: 30000000000000,
            gasMultiplier: 2,
            saveDeployments: true,
            live: true
        },
    },

    paths: {
        deploy: ['deploy/scripts']
    },

    tenderly: {
        forkNetwork: '1',
        project: TENDERLY_PROJECT || TENDERLY_TEST_PROJECT,
        username: TENDERLY_USERNAME
    },

    solidity: {
        compilers: [
            {
                version: '0.8.19',
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 2000
                    },
                    metadata: {
                        bytecodeHash: 'none'
                    },
                    outputSelection: {
                        '*': {
                            '*': ['storageLayout'] // Enable slots, offsets and types of the contract's state variables
                        }
                    }
                }
            }
        ]
    },

    dependencyCompiler: {
        paths: [
            '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol',
            'hardhat-deploy/solc_0.8/proxy/OptimizedTransparentUpgradeableProxy.sol'
        ]
    },

    namedAccounts: NamedAccounts,

    external: {
        deployments: {
            [DeploymentNetwork.Mainnet]: [`deployments/${DeploymentNetwork.Mainnet}`],
            [DeploymentNetwork.Tenderly]: [`deployments/${DeploymentNetwork.Tenderly}`],
            [DeploymentNetwork.Fantom]: [`deployments/${DeploymentNetwork.Fantom}`],
            [DeploymentNetwork.Base]: [`deployments/${DeploymentNetwork.Base}`],
            [DeploymentNetwork.Arbitrum]: [`deployments/${DeploymentNetwork.Arbitrum}`],
            [DeploymentNetwork.Mantle]: [`deployments/${DeploymentNetwork.Mantle}`],
            [DeploymentNetwork.Bsc]: [`deployments/${DeploymentNetwork.Bsc}`],
            [DeploymentNetwork.BaseGoerli]: [`deployments/${DeploymentNetwork.BaseGoerli}`],
            [DeploymentNetwork.Scroll]: [`deployments/${DeploymentNetwork.Scroll}`],
            [DeploymentNetwork.BeraArtio]: [`deployments/${DeploymentNetwork.BeraArtio}`],
            [DeploymentNetwork.NeonDevnet]: [`deployments/${DeploymentNetwork.NeonDevnet}`],
            [DeploymentNetwork.NeonMainnet]: [`deployments/${DeploymentNetwork.NeonMainnet}`],
            [DeploymentNetwork.SankoTestnet]: [`deployments/${DeploymentNetwork.SankoTestnet}`],
            [DeploymentNetwork.Telos]: [`deployments/${DeploymentNetwork.Telos}`]
        }
    },

    contractSizer: {
        alphaSort: true,
        runOnCompile: false,
        disambiguatePaths: false
    },

    // verify: {
    //     etherscan: {
    //         apiKey: ETHERSCAN_API_KEY
    //     }
    // },

    etherscan: {
        apiKey: {
            mainnet: ETHERSCAN_API_KEY,
            [DeploymentNetwork.NeonDevnet]: "test",
            [DeploymentNetwork.NeonMainnet]: "test"
        },
        customChains: [
            {
                network: DeploymentNetwork.NeonDevnet,
                chainId: 245022926,
                urls: {
                    apiURL: "https://devnet-api.neonscan.org/hardhat/verify",
                    browserURL: "https://devnet.neonscan.org"
                }
            },
            {
                network: DeploymentNetwork.NeonMainnet,
                chainId: 245022934,
                urls: {
                    apiURL: "https://api.neonscan.org/hardhat/verify",
                    browserURL: "https://neonscan.org"
                }
            }
        ]
    },

    watcher: {
        test: {
            tasks: [{ command: 'test' }],
            files: ['./test/**/*', './contracts/**/*', './deploy/**/*'],
            verbose: true
        }
    },

    mocha: mochaOptions()
};

export default config;
