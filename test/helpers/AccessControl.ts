import { AccessControlEnumerableUpgradeable } from '../../components/Contracts';
import { RoleIds } from '../../utils/Roles';
import { expect } from 'chai';
import { utils } from 'ethers';
import { camelCase } from 'lodash';

const { id } = utils;

export * from '../../utils/Roles';

export const expectRole = async (
    contract: AccessControlEnumerableUpgradeable,
    roleId: (typeof RoleIds)[number],
    adminRole: string,
    members: string[] = []
) => {
    expect(await contract.getRoleAdmin(roleId)).to.equal(adminRole);

    await expectRoleMembers(contract, roleId, members);
};

export const expectRoleMembers = async (
    contract: AccessControlEnumerableUpgradeable,
    roleId: (typeof RoleIds)[number],
    members: string[] = []
) => {
    const actualMembers = [];
    const memberCount = (await contract.getRoleMemberCount(roleId)).toNumber();

    for (let i = 0; i < memberCount; i++) {
        actualMembers.push(await contract.getRoleMember(roleId, i));
    }

    expect(actualMembers).to.have.lengthOf(members.length);
    expect(actualMembers).to.have.members(members);
};

export const expectRoles = async (
    contract: AccessControlEnumerableUpgradeable,
    roles: Record<string, (typeof RoleIds)[number]>
) => {
    const expectedRoles = Object.keys(roles).map((name) => ({
        methodName: camelCase(name),
        id: id(name)
    }));

    for (const { methodName, id } of expectedRoles) {
        const method = (contract as any)[methodName] as () => Promise<any>;
        expect(await method()).to.equal(id);
    }
};
