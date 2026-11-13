import unittest

import discord_changelog as changelog

REPOSITORY = {
    "full_name": "scolastico/babylon13",
    "html_url": "https://github.com/scolastico/babylon13",
    "owner": {"avatar_url": "https://avatars.example/owner.png"},
}


def push(count, subject="feat: change number {}"):
    return {
        "ref": "refs/heads/main",
        "compare": "https://github.com/scolastico/babylon13/compare/a...b",
        "repository": REPOSITORY,
        "pusher": {"name": "someone"},
        "head_commit": {"timestamp": "2026-11-13T08:00:00+01:00"},
        "commits": [
            {
                "id": f"{index:040x}",
                "url": f"https://github.com/scolastico/babylon13/commit/{index:040x}",
                "message": subject.format(index) + "\n\nBody that is not shown.",
                "author": {"name": "Author"},
            }
            for index in range(count)
        ],
    }


class CommitMode(unittest.TestCase):
    def test_every_commit_of_a_push_is_listed_in_order(self):
        embeds = changelog.commit_embeds(push(3))
        self.assertEqual(len(embeds), 1)
        lines = embeds[0]["description"].split("\n")
        self.assertEqual(len(lines), 3)
        for index, line in enumerate(lines):
            self.assertIn(f"change number {index}", line)
        self.assertNotIn("Body", embeds[0]["description"])
        self.assertEqual(embeds[0]["title"], "3 new commits on main")

    def test_large_pushes_continue_on_more_cards_without_dropping_commits(self):
        embeds = changelog.commit_embeds(push(300))
        self.assertGreater(len(embeds), 1)
        lines = [line for embed in embeds for line in embed["description"].split("\n")]
        self.assertEqual(len(lines), 300)
        self.assertIn("change number 299", lines[-1])
        for index, embed in enumerate(embeds, 1):
            self.assertLessEqual(len(embed["description"]), 4096)
            self.assertTrue(embed["title"].endswith(f"({index}/{len(embeds)})"))

    def test_markdown_in_subjects_is_escaped(self):
        embed = changelog.commit_embeds(push(1, "fix: *bold* `code` {}"))[0]
        self.assertIn(r"\*bold\* \`code\`", embed["description"])

    def test_branch_deletion_and_empty_pushes_post_nothing(self):
        self.assertEqual(changelog.commit_embeds({**push(2), "deleted": True}), [])
        self.assertEqual(changelog.commit_embeds(push(0)), [])


class ReleaseMode(unittest.TestCase):
    def release(self, body, **extra):
        return {
            "repository": REPOSITORY,
            "release": {
                "tag_name": "0.2.0",
                "name": "Music update",
                "body": body,
                "html_url": "https://github.com/scolastico/babylon13/releases/tag/0.2.0",
                "published_at": "2026-11-13T08:00:00Z",
                **extra,
            },
        }

    def test_release_description_becomes_the_card(self):
        embeds = changelog.release_embeds(self.release("## New\r\n- Server music"))
        self.assertEqual(len(embeds), 1)
        self.assertEqual(embeds[0]["title"], "Release Music update")
        self.assertEqual(embeds[0]["description"], "## New\n- Server music")
        self.assertEqual(embeds[0]["footer"]["text"], "0.2.0")

    def test_long_descriptions_are_split_not_cut(self):
        body = "\n".join(f"- entry {index} " + "x" * 80 for index in range(200))
        embeds = changelog.release_embeds(self.release(body))
        self.assertGreater(len(embeds), 1)
        self.assertEqual("\n".join(embed["description"] for embed in embeds), body)

    def test_prereleases_are_marked_and_empty_bodies_get_a_placeholder(self):
        embed = changelog.release_embeds(self.release("", prerelease=True))[0]
        self.assertTrue(embed["title"].startswith("Pre-release"))
        self.assertEqual(embed["description"], "No release notes.")


class Messages(unittest.TestCase):
    def test_only_the_first_message_mentions_the_role(self):
        result = changelog.messages([{"title": "a"}, {"title": "b"}], role="123")
        self.assertEqual(result[0]["content"], "<@&123>")
        self.assertEqual(result[0]["allowed_mentions"]["roles"], ["123"])
        self.assertNotIn("content", result[1])
        self.assertEqual(result[1]["allowed_mentions"], {"parse": []})

    def test_overlong_lines_are_split(self):
        chunks = changelog.chunk_lines(["y" * 9000], limit=4000)
        self.assertEqual([len(chunk) for chunk in chunks], [4000, 4000, 1000])


if __name__ == "__main__":
    unittest.main()
