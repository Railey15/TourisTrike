import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { handlePayMongoWebhook } from "../_shared/paymongo_webhook_handler.ts";

serve(handlePayMongoWebhook);
