#!/usr/bin/env bash

show_help() {
  cat << EOF
  Usage: snapzfs create|prune [-h <num_backups>][-d <num_backups>][-m <num_backups>][-y <num_backups>][-p][-r] <dataset>
  
  Subcommands:
    create                Create new snapshot
    prune                 Prune existing snapshots

  Options:
    -h <num_backups>      Number of hourly backups to retain
    -d <num_backups>      Number of daily backups to retain
    -m <num_backups>      Number of monthly backups to retain
    -y <num_backups>      Number of yearly backups to retain
    -p                    Prune snapshots following create (ignored for prune subcommand)
    -r                    Perform operation recursively

  Parameters:
    dataset               ZFS dataset for operation
EOF
}

create_snapshot() {
  DATASET=$1
  TYPE=$2
  RECURSIVE=$3

  TIME=$(date +'%Y_%m_%d-%H_%M_%S')

  # Continue if user has provided valid zfs dataset
  if [ -n "$DATASET" ] && zfs list -H -t filesystem $DATASET; then

    # Validate TYPE
    if [ -z "$TYPE" ]; then
      echo "Please provide a valid snapshot type. List of valid values includes hourly, daily, monthly and yearly."
      exit 1
    fi

    if [ -n "$RECURSIVE" ] && [ "$RECURSIVE" -eq "1" ]; then

      if zfs snapshot -r "$DATASET@$TIME-$TYPE"; then
        echo "Created $TYPE recursive snapshot of $DATASET @ $TIME."
      else
        echo "Failed to create $TYPE snapshot of $DATASET @ $TIME."
        exit 1
      fi

    else

      if zfs snapshot "$DATASET@$TIME-$TYPE"; then
        echo "Created $TYPE snapshot of $DATASET @ $TIME."
      else
        echo "Failed to create $TYPE snapshot of $DATASET @ $TIME."
        exit 1
      fi

    fi
  else
    echo "Please provide a valid ZFS dataset."
    exit 1
  fi
}

prune_snapshots() {
  DATASET=$1
  TYPE=$2
  COUNT=$3
  RECURSIVE=$4

  if [ -n "$DATASET" ] && zfs list -H -t filesystem $DATASET; then

    # Validate TYPE
    if [ -z "$TYPE" ]; then
      echo "Please provide a valid snapshot type. List of valid values includes hourly, daily, monthly and yearly."
      exit 1
    fi

    if [ -n "$COUNT" ]; then
      SNAPSHOT_COUNT=$(zfs list -H -t snapshot "$DATASET" | grep -c "$TYPE")
      if [ "$SNAPSHOT_COUNT" -gt "$COUNT" ]; then

        OLD_SNAPSHOT_COUNT=$((SNAPSHOT_COUNT - COUNT))
        echo "Pruning $OLD_SNAPSHOT_COUNT $TYPE snapshots."

        mapfile -t OLD_SNAPSHOTS < <(zfs list -H -t snapshot "$DATASET" | grep "$TYPE" | head -n "$OLD_SNAPSHOT_COUNT")
        for SNAPSHOT in "${OLD_SNAPSHOTS[@]}"; do
          if [ -n "$RECURSIVE" ] && [ "$RECURSIVE" == "true" ]; then
            if zfs destroy -r "$SNAPSHOT"; then
              echo "Recursively pruned $SNAPSHOT."
            else
              echo "Failed to recursively prune $SNAPSHOT."
            fi
          else
            if zfs destroy "$DATASET@$SNAPSHOT"; then
              echo "Pruned $SNAPSHOT."
            else
              echo "Failed to prune $SNAPSHOT."
            fi
          fi
        done

      else
          echo "Found equal or fewer snapshots than defined in retention policy. Skipping prune for $DATASET."
      fi
    else
      echo "Skipping prune of $TYPE snapshots for $DATASET. Retention policy undefined for snapshot type."
    fi
  else
    echo "Please provide a valid ZFS dataset."
    exit 1
  fi
}

# Confirm user is root. Required to execute zfs commands.
UID=$(id -u)
if [ "$UID" -ne 0 ]; then
  echo "User is not root."
  exit 1
fi

# Action to be performed. Create or prune snapshots?
ACTION=$1
if [ -z "$ACTION" ]; then
  echo "No action specified. Valid actions are create and prune."
  exit 1
elif [ "$ACTION" != "create" ] && [ "$ACTION" != "prune" ]; then
  echo "Unrecognized action ($ACTION). Valid actions are create and prune."
  exit 1
fi

# Start with second index
OPTIND=2
while getopts "h:d:m:y:pr" OPT; do
  case "$OPT" in
    h)
      HOURLY=$OPTARG
      ;;
    d)
      DAILY=$OPTARG
      ;;
    m)
      MONTHLY=$OPTARG
      ;;
    y)
      YEARLY=$OPTARG
      ;;
    p)
      PRUNE=1
      ;;
    r)
      RECURSIVE=1
      ;;
    *)
      show_help
      exit 0
      ;;
  esac
done

shift $((OPTIND-1))
DATASET_NAME=$*
EXIT_STATUS=0

# Create or prune hourly snapshots
if [ -n "$HOURLY" ]; then
  if [ "$ACTION" == "create" ]; then
    if ! create_snapshot "$DATASET_NAME" hourly "$RECURSIVE"; then
      EXIT_STATUS=1
    fi
  fi

  if [[ "$ACTION" == "prune" || (-n "$PRUNE"  && "$PRUNE" -eq "1") ]]; then
    if ! prune_snapshots "$DATASET_NAME" hourly "$HOURLY" "$RECURSIVE"; then
      EXIT_STATUS=1
    fi
  fi
fi

# Create or prune daily snapshots
if [ -n "$DAILY" ]; then
  if [ "$ACTION" == "create" ]; then
    if ! create_snapshot "$DATASET_NAME" daily "$RECURSIVE"; then
      EXIT_STATUS=1
    fi
  fi

  if [[ "$ACTION" == "prune" || (-n "$PRUNE"  && "$PRUNE" -eq "1") ]]; then
    if ! prune_snapshots "$DATASET_NAME" daily "$DAILY" "$RECURSIVE"; then
      EXIT_STATUS=1
    fi
  fi
fi

# Create or prune monthly snapshots
if [ -n "$MONTHLY" ]; then
  if [ "$ACTION" == "create" ]; then
    if ! create_snapshot "$DATASET_NAME" monthly "$RECURSIVE"; then
      EXIT_STATUS=1
    fi
  fi

  if [[ "$ACTION" == "prune" || (-n "$PRUNE"  && "$PRUNE" -eq "1") ]]; then
    if ! prune_snapshots "$DATASET_NAME" monthly "$MONTHLY" "$RECURSIVE"; then
      EXIT_STATUS=1
    fi
  fi
fi

# Create or prune yearly snapshots
if [ -n "$YEARLY" ]; then
  if [ "$ACTION" == "create" ]; then
    if ! create_snapshot "$DATASET_NAME" yearly "$RECURSIVE"; then
      EXIT_STATUS=1
    fi
  fi

  if [[ "$ACTION" == "prune" || (-n "$PRUNE"  && "$PRUNE" -eq "1") ]]; then
    if ! prune_snapshots "$DATASET_NAME" yearly "$YEARLY" "$RECURSIVE"; then
      EXIT_STATUS=1
    fi
  fi
fi

exit $EXIT_STATUS