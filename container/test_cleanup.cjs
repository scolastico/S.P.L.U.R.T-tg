const assert = require('node:assert/strict');
const cleanup = require('./cleanup-unstable.cjs');
const digest = 'sha256:' + 'a'.repeat(64);
async function check(organization) {
  const deleted = [];
  const versions = [
    { id: 1, name: 'old', metadata: { container: { tags: ['unstable-' + 'b'.repeat(40)] } } },
    { id: 2, name: digest, metadata: { container: { tags: ['unstable'] } } },
    { id: 3, name: 'release', metadata: { container: { tags: ['latest', '1.0.0'] } } },
    { id: 4, name: 'shared', metadata: { container: { tags: ['unstable', 'latest'] } } },
    { id: 5, name: 'unknown-untagged', metadata: { container: { tags: [] } } },
    { id: 6, name: 'unknown', metadata: { container: { tags: ['other'] } } },
  ];
  const github = {
    rest: { repos: { get: async () => ({ data: { owner: { type: organization ? 'Organization' : 'User' } } }) } },
    paginate: async (route, args) => {
      assert.match(route, organization ? /^GET \/orgs\// : /^GET \/users\//);
      assert.equal(args.per_page, 100);
      return versions;
    },
    request: async (route, args) => {
      assert.equal(route, 'DELETE ' + (organization ? '/orgs/{owner}' : '/users/{owner}')
        + '/packages/container/{package_name}/versions/{package_version_id}');
      assert.deepEqual(args, { owner: 'owner', package_name: 'babylon13', package_version_id: 1 },
        'DELETE must contain only route parameters, with no pagination or JSON body');
      deleted.push(args.package_version_id);
    },
  };
  await cleanup({ github, context: { repo: { owner: 'owner', repo: 'Babylon13' } },
    core: { info() {} }, currentDigest: digest });
  assert.deepEqual(deleted, [1], 'current, latest, releases and unknown images must survive');
}
(async () => {
  await check(false);
  await check(true);
  await assert.rejects(() => cleanup({ currentDigest: '' }), /Missing published digest/);
  console.log('Unstable cleanup protects release/latest/current manifests.');
})();
