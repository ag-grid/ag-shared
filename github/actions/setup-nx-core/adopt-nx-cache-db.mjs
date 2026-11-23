// Nx names its cache DB after the machine ID, so a cache restored from another runner is
// ignored. Copies the restored DB's rows into this machine's DB. Usage: `snapshot|adopt <state-file>`.
import { execFileSync } from 'node:child_process';
import { existsSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';

const DB_FILE = /-v\d+\.db$/;
// `cache_outputs` rows reference `task_details`, so order matters.
const TABLES = ['task_details', 'cache_outputs'];
// Nx task hashes are decimal, and Nx joins them onto cache paths; skip any row that isn't one.
const VALID_HASH = "hash <> '' AND hash NOT GLOB '*[^0-9]*'";

const [mode, stateFile] = process.argv.slice(2);
const workspaceDataDir = resolve(
    process.env.NX_WORKSPACE_DATA_DIRECTORY ??
        process.env.NX_PROJECT_GRAPH_CACHE_DIRECTORY ??
        join('.nx', 'workspace-data')
);

function listDbs() {
    if (!existsSync(workspaceDataDir)) {
        return [];
    }
    return readdirSync(workspaceDataDir).filter((name) => DB_FILE.test(name));
}

function warn(message) {
    console.log(`::warning title=Nx cache DB adoption::${message}`);
}

function snapshot() {
    const dbs = listDbs();
    writeFileSync(stateFile, JSON.stringify(dbs));
    console.log(dbs.length ? `Restored Nx cache DBs: ${dbs.join(', ')}` : 'No restored Nx cache DB.');
}

function sharedColumns(db, table) {
    const columns = (schema) =>
        db
            .prepare(`PRAGMA ${schema}.table_info(${table})`)
            .all()
            .map(({ name }) => name);
    const restored = new Set(columns('restored'));
    return columns('main').filter((name) => restored.has(name));
}

async function importRows(targetPath, sourcePath) {
    const { DatabaseSync } = await import('node:sqlite');
    const db = new DatabaseSync(targetPath);
    try {
        db.exec(`ATTACH DATABASE '${sourcePath.replaceAll("'", "''")}' AS restored`);
        const counts = [];
        // One transaction, so a failure leaves this machine's DB as it was.
        db.exec('BEGIN');
        try {
            for (const table of TABLES) {
                const columns = sharedColumns(db, table).join(', ');
                const { changes } = db
                    .prepare(
                        `INSERT OR IGNORE INTO main.${table} (${columns}) SELECT ${columns} FROM restored.${table} WHERE ${VALID_HASH}`
                    )
                    .run();
                counts.push(`${changes} ${table}`);
            }
            db.exec('COMMIT');
        } catch (error) {
            db.exec('ROLLBACK');
            throw error;
        }
        db.exec('DETACH DATABASE restored');
        return counts.join(', ');
    } finally {
        db.close();
    }
}

function removeDb(name) {
    const base = join(workspaceDataDir, name);
    for (const path of [base, `${base}-wal`, `${base}-shm`, base.replace(DB_FILE, (m) => m.replace('.db', '.lock'))]) {
        rmSync(path, { force: true });
    }
}

async function adopt() {
    if (!existsSync(stateFile)) {
        warn('No snapshot of the restored Nx cache DBs was taken; skipping.');
        return;
    }
    // The tidy step's `nx reset` may have deleted them.
    const restored = JSON.parse(readFileSync(stateFile, 'utf8')).filter(
        (name) => DB_FILE.test(name) && existsSync(join(workspaceDataDir, name))
    );
    if (restored.length === 0) {
        console.log('No restored Nx cache DB to adopt.');
        return;
    }

    // Cheapest command that creates the DB with its cache tables; `nx show projects` doesn't.
    const nx = resolve('node_modules', '.bin', 'nx');
    if (!existsSync(nx)) {
        warn(`${nx} not found; cannot create this machine's Nx DB.`);
        return;
    }
    execFileSync(nx, ['report'], { stdio: 'ignore' });

    const current = listDbs().filter((name) => !restored.includes(name));
    if (current.length === 0) {
        console.log(`This runner has the same machine ID as the one that saved the cache (${restored.join(', ')}).`);
        return;
    }
    if (current.length > 1) {
        warn(`Expected one new Nx DB, found ${current.join(', ')}; leaving the cache as is.`);
        return;
    }

    const target = join(workspaceDataDir, current[0]);
    for (const name of restored) {
        try {
            const counts = await importRows(target, join(workspaceDataDir, name));
            console.log(`Imported ${counts} from ${name} into ${current[0]}.`);
        } catch (error) {
            warn(`Could not import ${name}: ${error.message}`);
        } finally {
            // Even on failure: a saved archive must hold one DB for the next runner to pick its own.
            removeDb(name);
        }
    }
}

try {
    if (mode === 'snapshot') {
        snapshot();
    } else if (mode === 'adopt') {
        await adopt();
    } else {
        throw new Error(`Unknown mode "${mode}"; expected snapshot or adopt.`);
    }
} catch (error) {
    warn(error.message);
}
