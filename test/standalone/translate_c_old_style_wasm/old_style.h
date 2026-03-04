typedef int (*fn_ptr_old_style)();
typedef int (*fn_ptr_void)(void);

struct api_table {
    int (*create_thing)();
    int (*destroy_thing)(void);
};

int no_proto_func();
