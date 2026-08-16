import initOpaque, { opaque_client_invoke } from './opaque_client.js';

const opaqueReady = initOpaque();

globalThis.liflyOpaqueClientInvoke = async (requestJson) => {
  await opaqueReady;
  return opaque_client_invoke(requestJson);
};
