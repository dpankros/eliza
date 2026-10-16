
#!/usr/bin/env bash

#RUNTIME_DB='./agent/data/db.sqlite'
#SOURCE_DB='./agent/data/db_fiber_migration.sqlite'
#
#if [ -f "$RUNTIME_DB" ] && [ -f "$SOURCE_DB" ]; then
#    echo "Replacing $RUNTIME_DB with $SOURCE_DB"
#    rm "$RUNTIME_DB"
#    cp "$SOURCE_DB" "$RUNTIME_DB"
#fi

REDIS_DB=1

# vault-01 readiness: REDIS_HOST/REDIS_PORT unset = localhost:6379 (current behavior)
rc() { redis-cli -h "${REDIS_HOST:-localhost}" -p "${REDIS_PORT:-6379}" "$@"; }

#echo "Clearing redis fiber catch-up keys..."
#rc -n $REDIS_DB --scan --pattern "*fiber-creation-catchup*" | while IFS= read -r k; do rc -n $REDIS_DB DEL "$k"; done
#
#echo "Clearing emotion tagging extension catch-up keys..."
#rc -n $REDIS_DB --scan --pattern "*emotion_tagging_extension*" | while IFS= read -r k; do rc -n $REDIS_DB DEL "$k"; done
#rc -n $REDIS_DB --scan --pattern "*emotion-tagging-catchup*" | while IFS= read -r k; do rc -n $REDIS_DB DEL "$k"; done

#echo "Removing cached self-concepts..."
#rc -n $REDIS_DB --scan --pattern "*self_concept*" | while IFS= read -r k; do rc -n $REDIS_DB DEL "$k"; done
#
#echo "Removing cached psyches..."
#rc -n $REDIS_DB --scan --pattern "*psyche*" | while IFS= read -r k; do rc -n $REDIS_DB DEL "$k"; done
#rc -n $REDIS_DB --scan --pattern "*psyche_baseline*" | while IFS= read -r k; do rc -n $REDIS_DB DEL "$k"; done
#
#echo "Removing cached personality traits..."
#rc -n $REDIS_DB --scan --pattern "*personality_traits*" | while IFS= read -r k; do rc -n $REDIS_DB DEL "$k"; done
#
#echo "Removing fiber catch-up queues..."
#rc -n $REDIS_DB --scan --pattern "*q_fiber_created*" | while IFS= read -r k; do rc -n $REDIS_DB DEL "$k"; done
#rc -n $REDIS_DB --scan --pattern "*q_fiber_updated*" | while IFS= read -r k; do rc -n $REDIS_DB DEL "$k"; done
#
#echo "Removing thread catch-up queues..."
#rc -n $REDIS_DB --scan --pattern "*q_thread_created*" | while IFS= read -r k; do rc -n $REDIS_DB DEL "$k"; done
#rc -n $REDIS_DB --scan --pattern "*q_thread_updated*" | while IFS= read -r k; do rc -n $REDIS_DB DEL "$k"; done
#
#echo "Removing other catch up queues..."
#rc -n $REDIS_DB --scan --pattern "*summarization-*-catchup*" | while IFS= read -r k; do rc -n $REDIS_DB DEL "$k"; done
#rc -n $REDIS_DB --scan --pattern "*keyword-*-catchup*" | while IFS= read -r k; do rc -n $REDIS_DB DEL "$k"; done
#rc -n $REDIS_DB --scan --pattern "*keyword-refinement-*-catchup*" | while IFS= read -r k; do rc -n $REDIS_DB DEL "$k"; done
#rc -n $REDIS_DB --scan --pattern "*generation-*-embedding-catchup*" | while IFS= read -r k; do rc -n $REDIS_DB  DEL "$k"; done
#
#echo "Removing catch-up job metadata"
#rc -n $REDIS_DB --scan --pattern "_cap:catchUp:*" | while IFS= read -r k; do rc -n $REDIS_DB DEL "$k"; done
#
#echo "Removing Worker queue state (dedup entries, meta)"
#rc -n $REDIS_DB --scan --pattern "_cap:workerQueue:*" | while IFS= read -r k; do rc -n $REDIS_DB DEL "$k"; done
#rc -n $REDIS_DB --scan --pattern "_cap:queue:*" | while IFS= read -r k; do rc -n $REDIS_DB DEL "$k"; done
#rc -n $REDIS_DB --scan --pattern "_queue:*" | while IFS= read -r k; do rc -n $REDIS_DB DEL "$k"; done

#skip this for now
echo "Removing sleep sessions"
rc -n $REDIS_DB --scan --pattern "catchup:session:*" | while IFS= read -r k; do rc -n $REDIS_DB DEL "$k"; done
rc -n $REDIS_DB --scan --pattern 'nightly:in_flight:*' | while IFS= read -r k; do rc -n $REDIS_DB DEL "$k"; done

echo "Removing property locks (stale from crashed processes)"
rc -n $REDIS_DB --scan --pattern "*:readers:lock:*" | while IFS= read -r k; do rc -n $REDIS_DB DEL "$k"; done

echo "Removing stale RPC response streams (dead instances)"
rc -n $REDIS_DB --scan --pattern "function:responses:service:*" | while IFS= read -r k; do rc -n $REDIS_DB DEL "$k"; done
rc -n $REDIS_DB --scan --pattern "streaming:chunks:service:*" | while IFS= read -r k; do rc -n $REDIS_DB DEL "$k"; done

echo "Removing cached templates "
rc -n $REDIS_DB DEL  "fnd:generation:template:templates"

echo "Removing dead letter queue"
rc -n $REDIS_DB --scan --pattern "_sys:dlq" | while IFS= read -r k; do rc -n $REDIS_DB DEL "$k"; done

#nuclear option
#echo "Clearing all plugin Redis state..."
#rc -n $REDIS_DB FLUSHDB

echo ""
echo ""

export DEBUG_CONFIG=1
export LOG_LEVEL=debug

# note, because component directives tend to be cross-cutting (orthongonal) to fqsn, set them LAST.  They are usually "we want service X at debug, but microservice at info to avoid noise" scenarios
#export LOG_FILTER="*:warn,[serviceName='web_intelligence']:info,[serviceLevel='fnd']:warn,[serviceLevel='auto']:info,[serviceLevel='rte']:info,[serviceName='emotion_tagging_extension']:info,[fqsn='fnd.fabric.generation.generation_service']:debug,[component='MicroService']:info,[component='RemoteServiceProxy']:warn,[component='PubSub']:info,[component='WorkerQueue']:warn"
# 2026-09-04 (run19h stall diagnosis): the circadian orchestrator's decision-critical logs
# (single-flight drops, catch-up auto-advance decisions, night-settlement funnel, dead-night
# watchdog) are all log.debug() — invisible under [serviceLevel='auto']:info. The 09-04 run19h
# wedge produced zero operator-visible signal for that reason. Placed LAST (last-match-wins) so
# it also beats any cross-cutting component directive. Revert to :info once run19i is validated.
export LOG_FILTER="*:warn,[serviceLevel='auto']:info,[serviceLevel='rte']:info,[serviceName='emotion_tagging_extension']:info,[fqsn='fnd.fabric.generation.generation_service']:info,[fqsn='auto.fabric.memory.person_identification_service']:info,[fqsn='auto.fabric.memory.person_context_service']:info,[fqsn='auto.fabric.memory.fabric_service']:debug,[fqsn='ctrl.fabric.memory.person_disambiguation_service']:info,[component='MicroService']:info,[component='RemoteServiceProxy']:warn,[component='PubSub']:info,[component='WorkerQueue']:warn,[fqsn='auto.fabric.memory.message_reference_detect']:debug,[component='ConsistencyMiniAgent']:debug,[component='WorkerQueue']:debug,[fqsn='auto.fabric.memory.circadian_orchestrator_service']:debug"
#export LOG_FILTER="*:trace"
export ENHANCED_MEMORY_CONFIG_ROOT="/Users/dpankros/Developer/dpankros_plugin-enhanced-memory/config"
#export LOG_FILE="/Users/dpankros/Developer/dpankros_plugin-enhanced-memory/logs/app_$(date +%Y%m%d_%H%M%S).jsonl"
export LOG_FILE="/Users/dpankros/Developer/dpankros_plugin-enhanced-memory/logs/app_log.jsonl"
export LOG_DIR="/Users/dpankros/Developer/dpankros_plugin-enhanced-memory/logs"

if [ -f "$LOG_FILE" ]; then
    rm "$LOG_FILE"
fi

export POSTGRES_URL="${PG_DSN:-postgresql://postgres:postgres_dev_pass@localhost:5432/di_memory}"

#unset LOG_FILE
#unset REFL_LOG_FILE

#export LOG_LEVEL=silent
#export REFL_LOG_LEVEL=silent
#export LOG_FILE=""
#export REFL_LOG_FILE=""
#export DUAL_LOGGING=false
#export DISABLE_MRL_LOGGING=true

export TD_ENDPOINT_URL="https://8.17.147.153:10065/v1"
export TD_API_KEY="6284be31cf7443083be8f844ad0a8fef5f596709d5a7139f3e78fd283729d4f6778d9f0b37f0376a6ffd872dc1ef2e91356313564d1de4d8d31eac41353f8c0f"
export LOCAL_VLLM_API_KEY="sk-apxOG5ZDtpsAMyX4DXyqqRzj4uZ_rAMWIpn_mNxNcyw"
export SERPER_API_KEY="c2b589220b9607cac458fe4c564267f3d6abe74d"

export DISABLE_REASONING_PLUGIN=false
export DISABLE_PERSONALITY_PLUGIN=false
export DISABLE_PSYCHE_PLUGIN=false

# allow self-signed certificates
export NODE_TLS_REJECT_UNAUTHORIZED=0

# DI-agent allowlist for the R-9 ensure-self-row pass (Sprint #305 §S1).
# These are the eliza account ids of the two running agents (Ted + Britney),
# pulled from agent/data/db.sqlite `accounts` (stable across restarts).
# An EMPTY allowlist = HARD ZERO (no self rows minted), which leaves the catch-up
# parked forever on "self floor handle missing". Keep this in sync with the
# characters you actually load below.
export AGENT_ACCOUNT_ALLOWLIST="0c8316de-64cf-0848-bf74-4ebe43f8ea90,20d90364-741f-0cc2-b8f6-aff0d79cde70"

#export TD_ENDPOINT_URL="https://157.157.221.29:31504/v1"

export LOG_FIBER_PROMPTS_DIR='/Users/dpankros/Developer/dpankros_plugin-enhanced-memory/logs/fiber'

#printf 'Using log file: %s\n' "$LOG_FILE"
#export DUAL_LOGGING=true

echo "Using endpoint: $TD_ENDPOINT_URL"

#NODE_OPTIONS="--max-old-space-size=4096" pnpm dev --characters='./characters/test.character.json'

# cleanup any existing eliza processes
pkill -f "node.*eliza" || true
sleep 2 # make sure copy is done and everything is dead first

#pnpm install --force
pnpm install --filter @empathic-engines/plugin-enhanced-memory --force

NODE_OPTIONS="--max-old-space-size=4096" pnpm start --characters='/Users/dpankros/Developer/dpankros_plugin-enhanced-memory/characters/ted/test.character.json,/Users/dpankros/Developer/dpankros_plugin-enhanced-memory/characters/britney/britney.character.json'
