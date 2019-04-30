using VulkanCore
using GLFW

#window = GLFW.Window(Ptr{Cvoid}(C_NULL))
window = Ref{GLFW.Window}()
instance = Ref{vk.VkInstance}()
physicalDevice = vk.VK_NULL_HANDLE
logicalDevice = Ref{vk.VkDevice}()
graphicsQueue = Ref{vk.VkQueue}()
surface = Ref{vk.VkSurfaceKHR}()

#################### 1.Create instance ####################
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
    println(glfwExtensions)
    extensionCount = length(glfwExtensions)
    # CextNames = Vector{Cstring}(undef, 0)
    # for i = 1 : 2
    #     push!(CextNames, convert(Cstring, pointer(glfwExtensions[i])))
    #     #push!(CextNames, convert(Cstring, pointer("a")))
    # end
    CextNames = Vector{String}(undef, 0)
    for i = 1 : 2
        push!(CextNames, glfwExtensions[i])
        #push!(CextNames, convert(Cstring, pointer("a")))
    end
    # CextNames = Array{Cstring}(undef, 2)
    # CextNames[1] = pointer(glfwExtensions[2])
    # CextNames[2] = pointer(glfwExtensions[1])
    #a = convert(Cstring, pointer("b"))
    #b = convert(Cstring, pointer("b"))
    #CextNames = [pointer(glfwExtensions[2]), pointer(glfwExtensions[1])]
    #CextNames = [convert(Cstring, pointer(glfwExtensions[2])), convert(Cstring, pointer(glfwExtensions[1]))]
    #CextNames = [pointer(glfwExtensions[2]), pointer(glfwExtensions[1])]

    println(typeof(CextNames))
    println(typeof(glfwExtensions))
    #CextNames, extensionCount
    glfwExtensions, extensionCount
end

struct ExtensionProperties
    extensionName::String
    specVersion::Int
end
strings2pp(names::Vector{String}) = (ptr = Base.cconvert(Ptr{Cstring}, names); GC.@preserve ptr Base.unsafe_convert(Ptr{Cstring}, ptr))
vktuple2string(x) = x |> collect |> String |> s->strip(s, '\0')
ExtensionProperties(extension::vk.VkExtensionProperties) = ExtensionProperties(vktuple2string(extension.extensionName), Int(extension.specVersion))

function get_supported_extensions()
    extensionCountRef = Ref{Cuint}(0)
    vk.vkEnumerateInstanceExtensionProperties(C_NULL, extensionCountRef, C_NULL)
    extensionCount = extensionCountRef[]
    supportedExtensions = Vector{vk.VkExtensionProperties}(undef, extensionCount)
    vk.vkEnumerateInstanceExtensionProperties(C_NULL, extensionCountRef, supportedExtensions)
     for ext in supportedExtensions
        println(ExtensionProperties(ext))
    end
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
        #Base.unsafe_convert(Ptr{Cstring}, CextNames)
        #pointer(CextNames)
        #CextNames
        strings2pp(CextNames)
        #Base.cconvert(Ptr{Cstring}, CextNames)
    ))
    get_supported_extensions()
    createInfo
end

function createInstance()
    appInfo = getAppInfo()
    CextNames, extensionCount = getRequiredInstanceExtensions()
    createInfo = getCreateInfo(appInfo, CextNames, extensionCount)
    err = vk.vkCreateInstance(createInfo, C_NULL, instance)
    println(err)
    err
end

#################### 2.Using validation layers ####################
#################### 3.Pick Physical device ####################
function isDeviceSuitable(device)
    deviceProperties = Ref{vk.VkPhysicalDeviceProperties}();
    deviceFeatures = Ref{vk.VkPhysicalDeviceFeatures}();
    vk.vkGetPhysicalDeviceProperties(device, deviceProperties);
    vk.vkGetPhysicalDeviceFeatures(device, deviceFeatures);
    if (deviceFeatures[].geometryShader
        #&&deviceProperties[].deviceType == vk.VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU
        ) == false
        return false
    end

    indices = findQueueFamilies(device)
    if indices == -1
        return false
    end
    true
end

function pickPhysicalDevice()
    deviceCount = Ref{Cuint}(0)
    vk.vkEnumeratePhysicalDevices(instance[], deviceCount, C_NULL)
    if (deviceCount == 0)
        println("failed to find GPUs with Vulkan support!")
    end

    devices = Array{vk.VkPhysicalDevice}(undef, deviceCount[])
    vk.vkEnumeratePhysicalDevices(instance[], deviceCount, devices)

    for device in devices
        if (isDeviceSuitable(device))
            global physicalDevice = device
            break;
        end
    end
    if (physicalDevice == vk.VK_NULL_HANDLE)
        println("failed to find a suitable GPU!")
    end
end

#################### 4.Queue families ####################
function findQueueFamilies(device)
    queueFamilyCount = Ref{Cuint}(0)
    vk.vkGetPhysicalDeviceQueueFamilyProperties(device, queueFamilyCount, C_NULL);
    
    queueFamilies = Array{vk.VkQueueFamilyProperties}(undef, queueFamilyCount[])
    vk.vkGetPhysicalDeviceQueueFamilyProperties(device, queueFamilyCount, queueFamilies);
    
    indices = -1;
    i = 0; #queueFamilyIndex should start from 0
    for queueFamily in queueFamilies
        if (queueFamily.queueCount > 0 && (queueFamily.queueFlags & vk.VK_QUEUE_GRAPHICS_BIT == true))
            indices = i
            break
        end
        i += 1
    end
    indices
end

#################### 5.Create logical device ####################
function createLogicalDevice()
    indices = findQueueFamilies(physicalDevice)
    queuePriority = Ref{Float32}(1.0)
    queueCreateInfo = Ref(vk.VkDeviceQueueCreateInfo(
        vk.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        C_NULL,
        0, #flag
        indices, #queueFamilyIndex
        1, #queueCount
        Base.unsafe_convert(Ptr{Float32}, queuePriority)
    ))

    cc = Array{Int32}(undef, 1) # magical code
    cc[1] = 1 # magical code

    deviceFeatures = Ref{vk.VkPhysicalDeviceFeatures}();
    vk.vkGetPhysicalDeviceFeatures(physicalDevice, deviceFeatures);

    flags = vk.VK_DEBUG_REPORT_ERROR_BIT_EXT |
    vk.VK_DEBUG_REPORT_WARNING_BIT_EXT |
    vk.VK_DEBUG_REPORT_PERFORMANCE_WARNING_BIT_EXT

    exts = ["VK_KHR_win32_surface"]
    println("111", exts)
    createInfo = Ref(vk.VkDeviceCreateInfo(
        vk.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        C_NULL,
        #0, #flags
        flags,
        1, #createInfoCount
        Base.unsafe_convert(Ptr{vk.VkDeviceQueueCreateInfo}, queueCreateInfo),
        0, #enabledLayerCount, VilidationLayers is disabled
        C_NULL, #ppEnabledlayerNames
        0, #enabledExtensionCount
        C_NULL, #ppEnabledExtensionNames
        Base.unsafe_convert(Ptr{vk.VkPhysicalDeviceFeatures}, deviceFeatures)
    ))
    println("ready")
    
    err = vk.vkCreateDevice(physicalDevice, createInfo, C_NULL, logicalDevice)
    if err != vk.VK_SUCCESS
        println(err)
        println("failed to create logical device!")
    end

    vk.vkGetDeviceQueue(logicalDevice[], indices, 0, graphicsQueue)
end

#################### 6.Create window surface ####################
function createSurface()
    println(instance)
    println(window)
    surface = GLFW.CreateWindowSurface(instance, window)
    println(surface[])
end



function vkDestoryInstanceCallback()
    println("callback")
end



function render()
    #println("in render")
end

#################### 0.Setup ####################
function initVulkan()
    if (createInstance() != vk.VK_SUCCESS)
        println("failed to create instance!")
        exit(-1)
    end
    pickPhysicalDevice()
    createLogicalDevice()
    createSurface()
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
    while !GLFW.WindowShouldClose(window[])
        # Render here
        render()
        # Poll for and process events
        GLFW.PollEvents()
    end
end

function cleanup()
    vk.vkDestroyDevice(logicalDevice[], C_NULL)
    vk.vkDestroyInstance(instance[], C_NULL)
    GLFW.DestroyWindow(window[])
    GLFW.Terminate()
end

initWindow()
initVulkan()
mainLoop()
cleanup()