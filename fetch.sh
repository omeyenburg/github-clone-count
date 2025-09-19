#!/usr/bin/env bash

CLONES_REPO=clones
CLONES_FILE=clones.json
TIMESTAMP=$(date +%s)

public_repos=()
repo_page_index=1

while
    raw_repo_list=$(curl -s \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/users/$GITHUB_REPOSITORY_OWNER/repos?per_page=100&page=$repo_page_index")

    echo "$raw_repo_list"

    mapfile -t repos_on_page < <(echo "$raw_repo_list" | jq -r ".[].full_name")
    public_repos+=("${repos_on_page[@]}")
    ((repo_page_index++))

    [[ "$(echo "$raw_repo_list" | jq ". | length")" -eq 100 ]]
do true; done

git clone "https://x-access-token:$GITHUB_TOKEN@github.com/$GITHUB_REPOSITORY_OWNER/$CLONES_REPO.git"
git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"

cd "$CLONES_REPO"

stored=$(cat "$CLONES_FILE" 2>/dev/null)
if [[ -z "$stored" ]]; then
    stored='{"timestamp": 0, "repositories": {}}'
fi

stored_timestamp=$(echo "$stored" | jq ".timestamp")
stored=$(jq --argjson t "$TIMESTAMP" '.timestamp = $t' <<<"$stored")

for repo_path in "${public_repos[@]}"; do
    additional_clones=0
    additional_daily_unique=0

    clone_data=$(curl -s \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/repos/$repo_path/traffic/clones")

    while read -r clone_entry; do
        clone_timestamp=$(echo "$clone_entry" | jq -r ".timestamp")
        if [[ "$(date --date "$clone_timestamp" +%s)" -le "$stored_timestamp" ]]; then continue; fi

        ((additional_clones += $(echo "$clone_entry" | jq ".count")))
        ((additional_daily_unique += $(echo "$clone_entry" | jq ".uniques")))
    done < <(echo "$clone_data" | jq -c '.clones // [] | .[]')

    stored=$(jq --arg r "$repo_path" --argjson c "$additional_clones" --argjson u "$additional_daily_unique" '
      .repositories[$r] //= {"total_clones":0,"daily_unique":0} |
      .repositories[$r].total_clones += $c |
      .repositories[$r].daily_unique += $u
    ' <<<"$stored")
done

echo "$stored" >"$CLONES_FILE"

git add "$CLONES_FILE"
git commit -m "Update clone stats" && git push
rm -rf clones
