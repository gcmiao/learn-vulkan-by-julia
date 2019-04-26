using VulkanCore
using GLFW

window = GLFW.Window(Ptr{Cvoid}(C_NULL))
instance = Ref{vk.VkInstance}(C_NULL)

function getAppInfo()
    appInfo = Ref(vk.VkApplicationInfo(
        vk.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        C_NULL, #pNext
        pointer("Hello Triangle"),
        vk.VK_MAKE_VERSION(1, 0, 0),
        pointer("No Engine"),
        vk.VK_MAKE_VERSION(1, 0, 0),
        vk.VK_API_VERSION_1_0()
    ))
end

function getRequiredInstanceExtensions()
    glfwExtensions = GLFW.GetRequiredInstanceExtensions();
    extensionCount = length(glfwExtensions)
    CextNames = Vector{Cstring}(undef, 0)
    for i = 1:extensionCount
        push!(CextNames, pointer(glfwExtensions[i]))
    end
    CextNames, extensionCount
end

function getCreateInfo(appInfo, CextNames, extensionCount)
    createInfo = Ref(vk.VkInstanceCreateInfo(
        vk.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        C_NULL, #pNext
        UInt32(0), #flags
        Base.unsafe_convert(Ptr{vk.VkApplicationInfo}, appInfo),
        0, #layerCount
        C_NULL, #layerNames
        extensionCount,
        Base.unsafe_convert(Ptr{Cstring}, CextNames)
    ))
    createInfo
end

function createInstance()
    appInfo = getAppInfo()
    CextNames, extensionCount = getRequiredInstanceExtensions()
    createInfo = getCreateInfo(appInfo, CextNames, extensionCount)

    return vk.vkCreateInstance(createInfo, C_NULL, instance)
end

function isDeviceSuitable(device)
    return true
end

function pickPhysicalDevice()
    deviceCount = Ref{Cuint}(0)
    vk.vkEnumeratePhysicalDevices(instance[], deviceCount, C_NULL)
    if (deviceCount == 0)
        println("failed to find GPUs with Vulkan support!")
    end

    devices = Array{vk.VkPhysicalDevice}(undef, deviceCount[])
    vk.vkEnumeratePhysicalDevices(instance[], deviceCount, devices)

    physicalDevice = vk.VK_NULL_HANDLE
    for device in devices
        if (isDeviceSuitable(device))
            physicalDevice = device
            break;
        end
    end
    if (physicalDevice == vk.VK_NULL_HANDLE)
        println("filed to find a suitable GPU!")
    end
end

function createLogicalDevice()
    
end

function initVulkan()
    if (createInstance() != vk.VK_SUCCESS)
        println("failed to create instance!")
        exit(-1)
    end

    pickPhysicalDevice()
    createLogicalDevice()
end

function initWindow()
    GLFW.Init()
    GLFW.WindowHint(GLFW.CLIENT_API, GLFW.NO_API)
    GLFW.WindowHint(GLFW.RESIZABLE, false)
    # Create a window and its OpenGL context
    global window = GLFW.CreateWindow(640, 480, "Vulkan")
end

function mainLoop()
    # Loop until the user closes the window
    while !GLFW.WindowShouldClose(window)
        # Render here
        render()
        # Poll for and process events
        GLFW.PollEvents()
    end
end

function vkDestoryInstanceCallback()
    println("callback")
end

function cleanup()
    vk.vkDestroyInstance(instance[], C_NULL)
    GLFW.DestroyWindow(window)
    GLFW.Terminate()
end

function render()
    #println("in render")
end

#app = TriangleApp()
initVulkan()
initWindow()
mainLoop()
cleanup()