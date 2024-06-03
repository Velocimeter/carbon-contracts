import { DeployedContracts, deployProxy, execute, grantRole, InstanceName, setDeploymentMetadata } from '../../utils/Deploy';
import { Roles } from '../../utils/Roles';
import { DeployFunction } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';

const func: DeployFunction = async ({ getNamedAccounts }: HardhatRuntimeEnvironment) => {
    const { deployer, tank } = await getNamedAccounts();
    const carbonController = await DeployedContracts.CarbonController.deployed();

    await deployProxy({
        name: InstanceName.CarbonVortex,
        from: deployer,
        args: [carbonController.address]
    });

    const carbonVortex = await DeployedContracts.CarbonVortex.deployed();

    await grantRole({
        name: InstanceName.CarbonController,
        id: Roles.CarbonController.ROLE_FEES_MANAGER,
        member: carbonVortex.address,
        from: deployer
    });

    await execute({
        name: InstanceName.CarbonVortex,
        methodName: 'setTank',
        args: [tank],
        from: deployer
    });

    return true;
};

export default setDeploymentMetadata(__filename, func);
