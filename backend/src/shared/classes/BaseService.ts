import {MongoDatabase} from '#shared/database/index.js';
import {
  ClientSession,
  ReadPreference,
  ReadConcern,
  WriteConcern,
} from 'mongodb';

export abstract class BaseService {
  constructor(private readonly db: MongoDatabase) {}

  protected async _withTransaction<T>(
    operation: (session: ClientSession) => Promise<T>,
  ): Promise<T> {
    const client = await this.db.getClient();
    const MAX_RETRIES = 5;
    const txOptions = {
      readPreference: ReadPreference.primary,
      readConcern: new ReadConcern('snapshot'),
      writeConcern: new WriteConcern('majority'),
    };

    for (let attempt = 0; attempt < MAX_RETRIES; attempt++) {
      const session = client.startSession();
      try {
        session.startTransaction(txOptions);
        const result = await operation(session);
        await session.commitTransaction();
        await session.endSession();
        return result;
      } catch (error: any) {
        if (session.inTransaction()) await session.abortTransaction();
        await session.endSession();
        const isTransient =
          (Array.isArray(error?.errorLabels) &&
            error.errorLabels.includes('TransientTransactionError')) ||
          error?.code === 112 || // WriteConflict
          (typeof error?.message === 'string' && error.message.includes('Write conflict'));
        if (isTransient && attempt < MAX_RETRIES - 1) {
          await new Promise(r => setTimeout(r, 200 * Math.pow(2, attempt))); // 200ms, 400ms, 800ms, 1600ms
          continue;
        }
        throw error;
      }
    }

    throw new Error('Transaction failed after max retries');
  }
}
