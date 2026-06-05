import {MongoDatabase} from '#shared/database/index.js';
import {ClientSession} from 'mongodb';

export abstract class BaseService {
  constructor(private readonly db: MongoDatabase) {}

  protected async _withTransaction<T>(
    operation: (session: ClientSession | undefined) => Promise<T>,
  ): Promise<T> {
    // Skip MongoDB transactions to avoid WriteConflict from nested sessions.
    // Sub-services (questionService, questionBankService, etc.) start their own
    // sessions which conflict with any outer transaction session.
    const MAX_RETRIES = 5;

    for (let attempt = 0; attempt < MAX_RETRIES; attempt++) {
      try {
        return await operation(undefined);
      } catch (error: any) {
        const isTransient =
          (Array.isArray(error?.errorLabels) &&
            error.errorLabels.includes('TransientTransactionError')) ||
          error?.code === 112 || // WriteConflict
          (typeof error?.message === 'string' && error.message.includes('Write conflict'));
        if (isTransient && attempt < MAX_RETRIES - 1) {
          await new Promise(r => setTimeout(r, 200 * Math.pow(2, attempt)));
          continue;
        }
        throw error;
      }
    }

    throw new Error('Operation failed after max retries');
  }
}
