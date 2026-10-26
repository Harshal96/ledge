import { run } from "../src/index.ts";

await run(async (ctx) => {
  const response = await ctx.integration("github.issues.listUpdated", { repository: "owner/repo", page: 1 });
  return {
    events: [{ sourceKey: "issue/1", title: response.data[0].title }],
    state: { last: 1 }, recordMutations: [], summary: ctx.mode,
  };
});
