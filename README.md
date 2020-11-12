# bevry-actions/npm

Once your tests succeed, use this action to deploy to [npm](https://www.npmjs.com) for each new git release, as well as optionally for each new git commit to specific branches, to an npm tag.

## Example

For instance, for the [ambi](https://github.com/bevry/ambi) project, you can get [Deno](https://deno.land) compile target for the latest stable release via:

> https://unpkg.com/ambi/edition-deno/index.ts

Or for the latest commit via:

> https://unpkg.com/ambi@next/edition-deno/index.ts

## Install

And add the following to your GitHub Action workflow after your tests have completed and you have built your compile targets/documentation.

```yaml
- name: publish to npm
  uses: bevry-actions/npm@main
  with:
      npmAuthToken: ${{secrets.NPM_AUTH_TOKEN}}
      npmBranchTag: "master:next" # optional
```

## License

Public Domain via The Unlicense
