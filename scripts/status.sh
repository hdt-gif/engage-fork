#!/usr/bin/env bash
#
# One command that answers "is this actually working?" without asking anyone.
#
# Run it on YOUR OWN MACHINE:   scripts/status.sh
#
# Every line here is a claim you can check for yourself. Nothing is taken on
# trust -- each section runs a real command and prints what came back.
#
set -uo pipefail

REGION=us-east-2
INSTANCE=i-0c251de2dc1a35767
SG=sg-0619d031ef5e8a521
BUCKET=hseo-engage-backups-699752150149
KEY=~/.ssh/engage-hseo.pem
APP=3.151.238.7
SSH="ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -i $KEY ubuntu@$APP"

hdr(){ printf "\n\033[1m%s\033[0m\n" "$1"; }
ok(){  printf "  \033[32m✓\033[0m %s\n" "$1"; }
no(){  printf "  \033[31m✗\033[0m %s\n" "$1"; }
info(){ printf "    %s\n" "$1"; }

# ---------------------------------------------------------------
hdr "WHOSE INFRASTRUCTURE IS THIS?"
ID=$(aws sts get-caller-identity --output json 2>/dev/null)
if [ -n "$ID" ]; then
  ok "AWS account $(echo "$ID" | grep -o '"Account":[^,]*' | cut -d'"' -f4)"
  info "signed in as $(echo "$ID" | grep -o '"Arn":[^,]*' | cut -d'"' -f4)"
  info "region $REGION"
else
  no "not signed in to AWS — run: aws configure"
fi

# ---------------------------------------------------------------
hdr "IS THE SERVER ON?"
STATE=$(aws ec2 describe-instances --region $REGION --instance-ids $INSTANCE \
  --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null)
IP=$(aws ec2 describe-instances --region $REGION --instance-ids $INSTANCE \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text 2>/dev/null)
if [ "$STATE" = "running" ]; then
  ok "instance is running at $IP"
  info "costing roughly \$2/day while on"
else
  no "instance is $STATE"
  info "start it:  aws ec2 start-instances --region $REGION --instance-ids $INSTANCE"
  echo; echo "  (everything below needs it running)"; exit 0
fi

# ---------------------------------------------------------------
hdr "CAN YOU REACH IT?"
MYIP=$(curl -s --max-time 10 https://checkip.amazonaws.com 2>/dev/null)
ALLOWED=$(aws ec2 describe-security-groups --region $REGION --group-ids $SG \
  --query "SecurityGroups[0].IpPermissions[?FromPort==\`8000\`].IpRanges[].CidrIp" --output text 2>/dev/null)
if echo "$ALLOWED" | grep -q "$MYIP"; then
  ok "your IP ($MYIP) is allowed through the firewall"
else
  no "your IP ($MYIP) is NOT allowed — that is why it would hang"
  info "allowed: $ALLOWED"
fi
CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 "http://$APP:8000/" 2>/dev/null)
[ "$CODE" = "302" ] && ok "the app answers (HTTP $CODE — redirect to login is normal)" \
                    || no "the app did not answer properly (HTTP $CODE)"

# ---------------------------------------------------------------
hdr "IS EVERY PART OF IT RUNNING?"
UP=$($SSH 'cd ~/engage-fork && docker compose -f docker-compose.prod.yml ps --format "{{.Name}} {{.Status}}"' 2>/dev/null)
COUNT=$(echo "$UP" | grep -c "Up" 2>/dev/null || echo 0)
[ "$COUNT" -eq 6 ] && ok "all 6 containers up" || no "only $COUNT of 6 containers up"
echo "$UP" | sed 's/^/    /'

# ---------------------------------------------------------------
hdr "IS IT DOING ITS JOB?"
$SSH "docker exec calliope-postgres psql -U postgres -d postgres -t -A -F' ' -c \
  \"select (select count(*) from auth_user), (select count(*) from model), \
           (select count(*) from run where status='SUCCESS'), (select count(*) from run), \
           (select count(*) from parameter);\"" 2>/dev/null | while read u m ok_runs all_runs p; do
  info "$u user accounts"
  info "$m models"
  info "$ok_runs of $all_runs model runs finished successfully"
  info "$p reference parameters loaded"
done

# ---------------------------------------------------------------
hdr "ARE BACKUPS ACTUALLY HAPPENING?"
LOCAL=$($SSH 'ls -1t ~/backups/engage-db-*.sql.gz 2>/dev/null | head -1 | xargs -r basename' 2>/dev/null)
[ -n "$LOCAL" ] && ok "latest backup on the server: $LOCAL" || no "no backups found on the server"
S3LAST=$(aws s3 ls "s3://$BUCKET/postgres/" 2>/dev/null | sort | tail -1)
[ -n "$S3LAST" ] && ok "latest backup in S3: $(echo $S3LAST | awk '{print $4}')" \
                 || no "nothing in S3 — backups are not leaving the instance"
info "in S3: $(aws s3 ls s3://$BUCKET/ --recursive 2>/dev/null | wc -l | tr -d ' ') files"
CRON=$($SSH 'crontab -l 2>/dev/null | grep -c backup-engage' 2>/dev/null)
[ "${CRON:-0}" -ge 1 ] && ok "nightly job is scheduled" || no "nightly job is NOT scheduled"

# ---------------------------------------------------------------
hdr "WHAT IS CONNECTED, AND WHAT ISN'T?"
for v in MAPBOX_TOKEN NREL_API_KEY AWS_SES_FROM_EMAIL; do
  VAL=$($SSH "grep '^$v=' ~/engage-fork/.envs/.prod 2>/dev/null | cut -d= -f2-" 2>/dev/null)
  [ -n "$VAL" ] && ok "$v is set" || no "$v is empty — that feature is off"
done
HTTPS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 8 "https://$APP/" 2>/dev/null)
[ "$HTTPS" = "000" ] && no "no HTTPS — traffic is unencrypted" || ok "HTTPS answering"

# ---------------------------------------------------------------
hdr "IS ANYTHING BROKEN RIGHT NOW?"
ERRS=$($SSH 'cd ~/engage-fork && docker compose -f docker-compose.prod.yml logs app --since 24h 2>/dev/null | grep -c "Internal Server Error"' 2>/dev/null)
if [ "${ERRS:-0}" -eq 0 ]; then
  ok "no server errors in the last 24 hours"
else
  no "$ERRS server errors in the last 24 hours"
  info "see them:  $SSH 'cd ~/engage-fork && docker compose -f docker-compose.prod.yml logs app --since 24h | grep -A20 Traceback'"
fi

echo
