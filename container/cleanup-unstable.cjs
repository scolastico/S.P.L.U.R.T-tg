// Delete complete old unstable manifests, not just the moving tag. A unique
// unstable-SHA marker lets the next run clean up after a cancelled publisher.
module.exports = async function ({ github, context, core, currentDigest }) {
  if (!/^sha256:[0-9a-f]{64}$/.test(currentDigest || '')) throw new Error('Missing published digest');
  const owner = context.repo.owner;
  const repository = await github.rest.repos.get({ owner, repo: context.repo.repo });
  const organization = repository.data.owner.type === 'Organization';
  const prefix = organization ? '/orgs/{owner}' : '/users/{owner}';
  const route = prefix + '/packages/container/{package_name}/versions';
  const options = { owner, package_name: context.repo.repo.toLowerCase(), per_page: 100 };
  const versions = await github.paginate('GET ' + route, options);
  for (const version of versions) {
    if (version.name === currentDigest) continue;
    const tags = version.metadata?.container?.tags || [];
    const unstable = tag => tag === 'unstable' || /^unstable-[0-9a-f]{40}$/.test(tag);
    // Never delete latest, a release tag, or an unrecognized package version.
    if (!tags.length || !tags.some(unstable) || !tags.every(unstable)) continue;
    await github.request('DELETE ' + route + '/{package_version_id}', {
      ...options, package_version_id: version.id,
    });
    core.info('Deleted superseded unstable version ' + version.id);
  }
};
