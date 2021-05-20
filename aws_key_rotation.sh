#!/bin/bash -euo pipefail
#
# Usage:
#   $ aws-iam-user-key-rotation.sh [profile] [credential_file]
#

declare -x AWS_DEFAULT_PROFILE=${1:-default}
declare credential_file=${2:-~/.aws/credentials}
declare -x AWS_SHARED_CREDENTIALS_FILE=$credential_file

echo "${AWS_DEFAULT_PROFILE} プロファイルのアクセスキーをローテーションします。"

declare iam_user_name
iam_user_name=$(aws iam get-user | jq -r '.User.UserName')
declare current_access_keys
current_access_keys=$(aws iam list-access-keys)

echo "対象のIAMユーザーは ${iam_user_name} です。"

# AWSのアクセスキーは一度に2個までしか作成できないため先にチェックしておく
if (( $(echo "$current_access_keys" | jq '.AccessKeyMetadata | length') == 2 )); then
  echo "アクセスキーが2個存在しています。使用していないアクセスキーを削除してから再実行してください。" 1>&2
  exit 1
fi

cp "$credential_file"{,.bak}

declare new_credentials
new_credentials=$(aws iam create-access-key --user-name "$iam_user_name")
access_key_id=$(echo "$new_credentials" | jq -r '.AccessKey.AccessKeyId')
access_secrets_key=$(echo "$new_credentials" | jq -r '.AccessKey.SecretAccessKey')
echo "新規アクセスキーを作成しました。 $access_key_id"
echo "$access_key_id
$access_secrets_key
ap-northeast-1
" | aws configure > /dev/null
echo "クレデンシャルファイルを更新しました。"

declare updated_access_keys
echo "新しいアクセスキーで試行します。"

set +e
while :; do
  echo "5秒待機します..."
  sleep 5s

  # このコマンドは新しいアクセスキーで実行される
  updated_access_keys=$(aws iam list-access-keys 2> /dev/null)
  (( $? == 0 )) && break
done
set -e

# ここがfalseになることはないはず
if (( $(echo "$updated_access_keys" | jq '.AccessKeyMetadata | length') != 2 )); then
  echo "アクセスキーが2個存在していません。何かおかしいようです。" 1>&2
  exit 1
fi

aws iam delete-access-key --user-name "$iam_user_name" --access-key-id "$(echo "$current_access_keys" | jq -r '.AccessKeyMetadata[0].AccessKeyId')"
echo "古いアクセスキーを削除しました。"
