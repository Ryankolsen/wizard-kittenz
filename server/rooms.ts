const SYSTEM_USER = '00000000-0000-0000-0000-000000000000';
const COLLECTION = 'rooms';

const rpcRegisterRoom: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
    const { room_code, match_id } = JSON.parse(payload);
    nk.storageWrite([{
        collection: COLLECTION, key: room_code, userId: SYSTEM_USER,
        value: { match_id }, permissionRead: 2, permissionWrite: 0,
    }]);
    return JSON.stringify({ success: true });
};

const rpcFindRoom: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
    const { room_code } = JSON.parse(payload);
    const objects = nk.storageRead([{ collection: COLLECTION, key: room_code, userId: SYSTEM_USER }]);
    return JSON.stringify({ match_id: objects.length > 0 ? objects[0].value.match_id : '' });
};

const rpcDeleteRoom: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
    const { room_code } = JSON.parse(payload);
    nk.storageDelete([{ collection: COLLECTION, key: room_code, userId: SYSTEM_USER }]);
    return JSON.stringify({ success: true });
};

function InitModule(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, initializer: nkruntime.Initializer) {
    initializer.registerRpc('register_room', rpcRegisterRoom);
    initializer.registerRpc('find_room', rpcFindRoom);
    initializer.registerRpc('delete_room', rpcDeleteRoom);
}
